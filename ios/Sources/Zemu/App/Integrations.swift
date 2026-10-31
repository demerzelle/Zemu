import UIKit
import MediaPlayer
import UserNotifications
import ZemuCore

/**
 * iOS system integration: Now Playing / Control Center, keeping the screen awake during playback
 * and new-episode notifications.
 */
@MainActor
final class Integrations: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Integrations()

    private var commandsInstalled = false
    private weak var player: PlayerModel?
    private var artwork: [String: MPMediaItemArtwork] = [:]

    // MARK: Session

    func sessionStarted(_ s: Session) {
        if s.settings.notifyNewEpisodes { requestNotificationPermission() }
    }

    // MARK: Playback

    func playbackStarted(_ p: PlayerModel) {
        player = p
        installRemoteCommands()
        preventSleep(true)
        updateNowPlaying(p)
    }

    func playbackStopped(_ p: PlayerModel) {
        guard player === p || player == nil else { return }
        player = nil
        preventSleep(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func updateNowPlaying(_ p: PlayerModel) {
        guard player === p else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: p.label ?? p.title,
            MPMediaItemPropertyArtist: p.label != nil ? p.title : "Zemu",
            MPMediaItemPropertyPlaybackDuration: Double(p.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(p.positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: p.isPlaying ? p.speed : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let poster = p.meta.posterUrl {
            if let art = artwork[poster] { info[MPMediaItemPropertyArtwork] = art }
            else {
                Task {
                    guard let img = await ImageLoader.shared.image(poster, maxPixel: 600) else { return }
                    let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    artwork = [poster: art]
                    updateNowPlaying(p)
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = p.isPlaying ? .playing : .paused
        preventSleep(p.isPlaying)
    }

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.player?.togglePlay(); return .success }
        c.playCommand.addTarget { [weak self] _ in self?.player?.setPaused(false); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.player?.setPaused(true); return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in self?.player?.seekBy(10_000); return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in self?.player?.seekBy(-10_000); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in
            guard let p = self?.player, p.upNext != nil else { return .noActionableNowPlayingItem }
            p.playNextNow(); return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let p = self?.player, let e = e as? MPChangePlaybackPositionCommandEvent, p.durationMs > 0 else { return .commandFailed }
            p.seek(toFraction: e.positionTime * 1000 / Double(p.durationMs))
            return .success
        }
    }

    private func preventSleep(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    // MARK: Notifications

    private var canNotify: Bool { !tvOS }

    func requestNotificationPermission() {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewEpisodes(_ items: [NewEpisodesItem]) {
        #if !os(tvOS) // tvOS notifications can only badge the icon.
        guard canNotify else { return }
        for item in items.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = item.meta.title
            content.body = item.count == 1 ? "New episode: \(item.latest.label)" : "\(item.count) new episodes, latest: \(item.latest.label)"
            content.userInfo = ["type": item.meta.type, "id": item.meta.id]
            content.sound = .default
            let req = UNNotificationRequest(identifier: "\(item.meta.id)|\(item.latest.id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
        #endif
    }

    #if !os(tvOS)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let type = info["type"] as? String, let id = info["id"] as? String else { return }
        await MainActor.run {
            AppModel.shared.openDetails(type: type, id: id)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    #endif
}
