import UIKit
import VideoToolbox
import ZemuCore

/** What this iPhone or iPad decodes and shows, for "Best for this device". */
enum DeviceCaps {
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
            maxResolution: widest >= 2400 ? 2160 : widest >= 1800 ? 1440 : 1080,
            hevc: true,
            av1: true,
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
