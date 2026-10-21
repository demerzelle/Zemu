import Foundation
import Observation
import ZemuCore

/** A title (or episode) saved on this Mac for offline playback. */
struct DownloadItem: Codable, Hashable, Identifiable {
    let id: String
    let meta: Meta
    let videoId: String
    let label: String?
    let path: String
}

/**
 * Downloads for offline playback, into ~/Movies/Zemu Next. Shared by every profile. A download
 * that was interrupted when Zemu quit shows as failed (delete it and start again).
 */
@MainActor @Observable
final class Downloads: NSObject, URLSessionDownloadDelegate {
    static let shared = Downloads()

    private(set) var items: [DownloadItem]
    /** Progress 0–1 and bytes so far of downloads in flight; failed ones are listed in [failed]. */
    private(set) var progress: [String: (fraction: Double, bytes: Int64)] = [:]
    private(set) var failed: Set<String> = []
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private let file = AppPaths.support.appendingPathComponent("downloads.json")
    @ObservationIgnored private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    static var folder: URL {
        let u = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zemu Next", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private override init() {
        items = (try? Data(contentsOf: AppPaths.support.appendingPathComponent("downloads.json")))
            .flatMap { try? JSONDecoder().decode([DownloadItem].self, from: $0) } ?? []
        super.init()
        failed = Set(items.filter { !FileManager.default.fileExists(atPath: $0.path) }.map(\.id))
    }

    func isDone(_ item: DownloadItem) -> Bool { progress[item.id] == nil && !failed.contains(item.id) && FileManager.default.fileExists(atPath: item.path) }

    func sizeBytes(_ item: DownloadItem) -> Int64 {
        progress[item.id]?.bytes ?? ((try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int64) ?? 0)
    }

    /** Starts downloading a stream; returns an error to show, or nil when it started. */
    func start(meta: Meta, videoId: String, label: String?, stream: ParsedStream) -> String? {
        guard let raw = stream.raw.url, let url = URL(string: raw) else { return "This stream has no direct link." }
        if items.contains(where: { $0.meta.id == meta.id && $0.videoId == videoId }) { return "Already downloaded or downloading." }
        let free = (try? Self.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? .max
        if let size = stream.raw.behaviorHints?.videoSize, size > free {
            return String(format: "Not enough space: needs %.1f GB, %.1f GB free.", Double(size) / 1e9, Double(free) / 1e9)
        }
        let fileName = stream.raw.behaviorHints?.filename
        let ext = fileName.map { ($0 as NSString).pathExtension }.flatMap { (2...4).contains($0.count) ? $0 : nil } ?? "mkv"
        let base = [meta.title, label].compactMap { $0 }.joined(separator: " - ")
            .replacingOccurrences(of: "[^A-Za-z0-9 ._-]", with: "", options: .regularExpression).prefix(80)
        let name = "\(base.isEmpty ? "video" : String(base)) [\(nowMs())].\(ext)"
        let id = UUID().uuidString
        var req = URLRequest(url: url)
        stream.raw.behaviorHints?.proxyHeaders?.request.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let task = session.downloadTask(with: req)
        task.taskDescription = id
        tasks[id] = task
        progress[id] = (0, 0)
        items.append(DownloadItem(id: id, meta: meta.slim(), videoId: videoId, label: label, path: Self.folder.appendingPathComponent(name).path))
        save()
        task.resume()
        return nil
    }

    /** Cancels it if still running and deletes the file. */
    func remove(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        progress[item.id] = nil
        failed.remove(item.id)
        try? FileManager.default.removeItem(atPath: item.path)
        items.removeAll { $0.id == item.id }
        save()
    }

    /** Plays a downloaded file (no network needed), from where it was left. */
    func play(_ item: DownloadItem) {
        let app = AppModel.shared
        let s = app.session
        let start = s.store.history.first { $0.meta.id == item.meta.id && $0.videoId == item.videoId }
            .flatMap { (0.02...0.95).contains($0.progress) ? $0.positionMs : nil } ?? 0
        let stream = StreamParser.parse(Stream(name: "Downloaded", url: URL(fileURLWithPath: item.path).absoluteString,
                                               behaviorHints: StreamBehaviorHints(filename: (item.path as NSString).lastPathComponent)),
                                        addonName: "Downloaded", trustDirectLinks: true)
        app.player?.close()
        app.player = PlayerModel(session: s, meta: item.meta, videoId: item.videoId, label: item.label, candidates: [PlayCandidate(stream)], subtitles: [], startMs: start)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: URLSessionDownloadDelegate (delivered on the main queue)

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskDescription ?? ""
        MainActor.assumeIsolated {
            progress[id] = (totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0, totalBytesWritten)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskDescription ?? ""
        let ok = (downloadTask.response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
        // The temporary file is deleted when this returns, so move it now.
        let path = MainActor.assumeIsolated { items.first { $0.id == id }?.path }
        var moved = false
        if ok, let path { moved = (try? FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: path))) != nil }
        MainActor.assumeIsolated {
            progress[id] = nil
            tasks[id] = nil
            if !moved { failed.insert(id) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        let id = task.taskDescription ?? ""
        MainActor.assumeIsolated {
            progress[id] = nil
            tasks[id] = nil
            failed.insert(id)
        }
    }
}

import SwiftUI

/** Titles saved for offline playback: progress while downloading, then Play; Delete frees the space. */
struct DownloadsView: View {
    var dl = Downloads.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Downloads").font(.z(size: 28, weight: .black)).padding(.top, 40)
            Text(dl.items.isEmpty ? "Nothing downloaded yet. On a title page, right-click a stream (or press O) and pick \"Download for Offline\"."
                 : "Saved in Movies → Zemu Next, so they play without internet.")
                .font(.z(size: 13)).foregroundStyle(Palette.textSecondary).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(dl.items) { item in row(item) }
                }
                .padding(.bottom, 60)
            }
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: DownloadItem) -> some View {
        let done = dl.isDone(item)
        let failed = dl.failed.contains(item.id)
        let gb = Double(dl.sizeBytes(item)) / 1e9
        let status = done ? String(format: "Ready · %.1f GB", gb)
            : failed ? "Download failed"
            : String(format: "Downloading… %d%%  (%.1f GB)", Int((dl.progress[item.id]?.fraction ?? 0) * 100), gb)
        return HStack(spacing: 16) {
            RemoteImage(url: item.meta.preferredPosterUrl, maxPixel: 200).frame(width: 60, height: 90).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text([item.meta.title, item.label].compactMap { $0 }.joined(separator: " · ")).font(.z(size: 16, weight: .semibold)).lineLimit(1)
                Text(status).font(.z(size: 13)).foregroundStyle(failed ? Palette.cached : Palette.textSecondary)
                if !done && !failed { ProgressView(value: dl.progress[item.id]?.fraction ?? 0).frame(maxWidth: 320).tint(P.accent) }
            }
            Spacer()
            if done {
                ZButton(title: "Play", icon: "play.fill", primary: true) { dl.play(item) }
                ZButton(title: "Show in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
            }
            ZButton(title: done || failed ? "Delete" : "Cancel", icon: "trash") { dl.remove(item) }
        }
        .padding(12)
        .zSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), fill: P.surface)
    }
}
