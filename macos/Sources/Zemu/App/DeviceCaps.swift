import AppKit
import VideoToolbox
import ZemuCore

/** What this Mac decodes and shows, for "Best for this Mac". */
enum DeviceCaps {
    @MainActor
    static func detect() -> DeviceCapabilities {
        let hwHevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let hwAv1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let mpv = MPV.available
        // Widest attached display in pixels: 4K streams are worth it on Retina and 4K screens.
        let widest = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 1920
        let hdr = NSScreen.screens.contains { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 }
        // mpv decodes every audio format in software; AVPlayer can't do DTS or TrueHD.
        let audio: Set<AudioCodec> = mpv ? Set(AudioCodec.allCases) : [.aac, .flac, .opus, .dd, .ddp, .atmos]
        return DeviceCapabilities(
            maxResolution: widest >= 3000 ? 2160 : widest >= 2400 ? 1440 : widest >= 1800 ? 1080 : 720,
            hevc: hwHevc || mpv,
            av1: hwAv1 || mpv,
            // mpv's OpenGL output can't apply Dolby Vision's reshaping (profile 5 shows green/purple).
            dolbyVision: false,
            hdr10: hdr,
            hdr10Plus: false,
            playableAudio: audio,
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
            ("mpv engine (MKV, ASS subtitles, every codec)", MPV.available),
        ]
    }
}
