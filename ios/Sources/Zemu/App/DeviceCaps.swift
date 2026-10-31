import Darwin
import UIKit
import VideoToolbox
import ZemuCore

/** What this iPhone or iPad decodes and shows, for "Best for this device". */
enum DeviceCaps {
    /** Apple TV HD (A8, 2 GB, 1080p): keeps effects off and memory low so browsing and video stay smooth. */
    static let isLowEnd: Bool = {
        #if os(tvOS)
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim.hasPrefix("AppleTV5") }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &name, &size, nil, 0)
        return String(cString: name).hasPrefix("AppleTV5")
        #else
        return false
        #endif
    }()

    @MainActor
    static func detect() -> DeviceCapabilities {
        let hwHevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let hwAv1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let screen = UIScreen.main
        let widest = max(screen.nativeBounds.width, screen.nativeBounds.height)
        let hdr = screen.potentialEDRHeadroom > 1
        // mpv (MPVKit's ffmpeg) decodes every audio format in software.
        return DeviceCapabilities(
            // 4K is worth it on iPads and AirPlay; phones top out at 1440p-ish panels.
            maxResolution: isLowEnd ? 1080 : widest >= 2400 ? 2160 : widest >= 1800 ? 1440 : 1080,
            // Software decoding these can't keep up on the A8, so "Best for this device" should rank them lower.
            hevc: !isLowEnd || hwHevc,
            av1: !isLowEnd || hwAv1,
            // mpv's Vulkan output can't apply Dolby Vision's reshaping (profile 5 shows green/purple).
            dolbyVision: false,
            hdr10: hdr,
            hdr10Plus: false,
            playableAudio: Set(AudioCodec.allCases),
            hardwareHevc: hwHevc,
            hardwareAv1: hwAv1
        )
    }

    static func summary(_ c: DeviceCapabilities) -> [(String, Bool)] {
        [
            ("4K output", c.maxResolution >= 2160),
            ("HEVC / H.265 hardware decoding", c.hardwareHevc),
            ("AV1 hardware decoding", c.hardwareAv1),
            ("HDR display (EDR)", c.hdr10),
            ("Dolby Vision", c.dolbyVision),
            ("Dolby Digital+ / Atmos", c.canPlay(.ddp)),
            ("Dolby TrueHD", c.canPlay(.truehd)),
            ("DTS / DTS-HD", c.canPlay(.dtsHd)),
            ("mpv engine (MKV, ASS subtitles, every codec)", true),
        ]
    }
}
