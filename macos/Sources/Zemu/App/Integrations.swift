import AppKit
import MediaPlayer
import IOKit.pwr_mgt
import UserNotifications
import ZemuCore

/**
 * macOS system integration: Now Playing / media keys, keeping the display awake during playback,
 * new-episode notifications and the Dock menu's Continue Watching.
 */
@MainActor
final class Integrations: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Integrations()

    private var sleepAssertion: IOPMAssertionID = 0
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
        if on && sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Zemu is playing video" as CFString, &sleepAssertion)
        } else if !on && sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    // MARK: Notifications

    /** Notifications need a real app bundle; running the bare binary (swift run) skips them. */
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func requestNotificationPermission() {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewEpisodes(_ items: [NewEpisodesItem]) {
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
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let type = info["type"] as? String, let id = info["id"] as? String else { return }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            AppModel.shared.openDetails(type: type, id: id)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: Dock menu

    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        let entries = AppModel.shared.session.inProgress.prefix(6)
        if !entries.isEmpty {
            let header = NSMenuItem(title: "Continue Watching", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for e in entries {
                let title = [e.meta.title, e.label].compactMap { $0 }.joined(separator: " · ") + "  (\(Int(e.progress * 100))%)"
                let item = NSMenuItem(title: title, action: #selector(resumeFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = e.meta.id
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc func resumeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let e = AppModel.shared.session.inProgress.first(where: { $0.meta.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.resume(e)
    }
}
