package com.zemu.tv.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** Icons not in material-icons-core, drawn from the Material Symbols paths. */
object AppIcons {
    private fun icon(name: String, path: String) = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
        .addPath(PathParser().parsePathString(path).toNodes(), fill = SolidColor(Color.Black))
        .build()

    val Tv: ImageVector = icon(
        "Tv",
        "M21,3H3C1.9,3 1,3.9 1,5v12c0,1.1 0.9,2 2,2h5v2h8v-2h5c1.1,0 1.99,-0.9 1.99,-2L23,5C23,3.9 22.1,3 21,3zM21,17H3V5h18V17z",
    )

    val Movie: ImageVector = icon(
        "Movie",
        "M18,4l2,4h-3l-2,-4h-2l2,4h-3l-2,-4H8l2,4H7L5,4H4C2.9,4 2.01,4.9 2.01,6L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V4H18z",
    )

    /** Sparkle, for Anime. */
    val Anime: ImageVector = icon(
        "Anime",
        "M12,2l2.4,6.6L21,11l-6.6,2.4L12,20l-2.4,-6.6L3,11l6.6,-2.4L12,2zM19,15l1.1,2.9L23,19l-2.9,1.1L19,23l-1.1,-2.9L15,19l2.9,-1.1L19,15z",
    )

    val Palette: ImageVector = icon(
        "Palette",
        "M12,2C6.49,2 2,6.49 2,12s4.49,10 10,10c1.38,0 2.5,-1.12 2.5,-2.5c0,-0.61 -0.23,-1.2 -0.64,-1.67c-0.08,-0.1 -0.13,-0.21 -0.13,-0.33c0,-0.28 0.22,-0.5 0.5,-0.5H16c3.31,0 6,-2.69 6,-6C22,6.04 17.51,2 12,2zM6.5,13C5.67,13 5,12.33 5,11.5S5.67,10 6.5,10S8,10.67 8,11.5S7.33,13 6.5,13zM9.5,9C8.67,9 8,8.33 8,7.5S8.67,6 9.5,6S11,6.67 11,7.5S10.33,9 9.5,9zM14.5,9C13.67,9 13,8.33 13,7.5S13.67,6 14.5,6S16,6.67 16,7.5S15.33,9 14.5,9zM17.5,13c-0.83,0 -1.5,-0.67 -1.5,-1.5S16.67,10 17.5,10s1.5,0.67 1.5,1.5S18.33,13 17.5,13z",
    )

    val Pause: ImageVector = icon("Pause", "M6,19h4V5H6v14zM14,5v14h4V5h-4z")
    val Play: ImageVector = icon("Play", "M8,5v14l11,-7z")
    val Rewind: ImageVector = icon(
        "Rewind",
        "M12,5V1L7,6l5,5V7c3.31,0 6,2.69 6,6s-2.69,6 -6,6s-6,-2.69 -6,-6H4c0,4.42 3.58,8 8,8s8,-3.58 8,-8S16.42,5 12,5z",
    )
    val Forward: ImageVector = icon(
        "Forward",
        "M12,5V1l5,5l-5,5V7c-3.31,0 -6,2.69 -6,6s2.69,6 6,6s6,-2.69 6,-6h2c0,4.42 -3.58,8 -8,8s-8,-3.58 -8,-8S7.58,5 12,5z",
    )
    val Audio: ImageVector = icon(
        "Audio",
        "M3,9v6h4l5,5V4L7,9H3zM16.5,12c0,-1.77 -1.02,-3.29 -2.5,-4.03v8.05c1.48,-0.73 2.5,-2.25 2.5,-4.02zM14,3.23v2.06c2.89,0.86 5,3.54 5,6.71s-2.11,5.85 -5,6.71v2.06c4.01,-0.91 7,-4.49 7,-8.77s-2.99,-7.86 -7,-8.77z",
    )
    val Subtitles: ImageVector = icon(
        "Subtitles",
        "M20,4H4C2.9,4 2,4.9 2,6v12c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6C22,4.9 21.1,4 20,4zM4,12h4v2H4V12zM14,18H4v-2h10V18zM20,18h-4v-2h4V18zM20,14H10v-2h10V14z",
    )
    val Speed: ImageVector = icon(
        "Speed",
        "M20.38,8.57l-1.23,1.85a8,8 0,0 1,-0.22 7.58L5.07,18A8,8 0,0 1,15.58 6.85l1.85,-1.23A10,10 0,0 0,3.35 19a2,2 0,0 0,1.72 1h13.85a2,2 0,0 0,1.74 -1a10,10 0,0 0,-0.27 -10.44zM10.59,15.41a2,2 0,0 0,2.83 0l5.66,-8.49l-8.49,5.66a2,2 0,0 0,0 2.83z",
    )
    val Aspect: ImageVector = icon(
        "Aspect",
        "M19,12h-2v3h-3v2h5v-5zM7,9h3V7H5v5h2V9zM21,3H3c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h18c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM21,19.01H3V4.99h18v14.02z",
    )
    val Next: ImageVector = icon("Next", "M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z")
    val ThumbUp: ImageVector = icon(
        "ThumbUp",
        "M1,21h4V9H1v12zM23,10c0,-1.1 -0.9,-2 -2,-2h-6.31l0.95,-4.57l0.03,-0.32c0,-0.41 -0.17,-0.79 -0.44,-1.06L14.17,1L7.59,7.59C7.22,7.95 7,8.45 7,9v10c0,1.1 0.9,2 2,2h9c0.83,0 1.54,-0.5 1.84,-1.22l3.02,-7.05c0.09,-0.23 0.14,-0.47 0.14,-0.73v-2z",
    )
    val ThumbDown: ImageVector = icon(
        "ThumbDown",
        "M15,3H6c-0.83,0 -1.54,0.5 -1.84,1.22l-3.02,7.05c-0.09,0.23 -0.14,0.47 -0.14,0.73v2c0,1.1 0.9,2 2,2h6.31l-0.95,4.57l-0.03,0.32c0,0.41 0.17,0.79 0.44,1.06L9.83,23l6.59,-6.59c0.36,-0.36 0.58,-0.86 0.58,-1.41V5c0,-1.1 -0.9,-2 -2,-2zM19,3v12h4V3h-4z",
    )
    val Heart: ImageVector = icon(
        "Heart",
        "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5C2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3C19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z",
    )
    val HeartOutline: ImageVector = icon(
        "HeartOutline",
        "M16.5,3c-1.74,0 -3.41,0.81 -4.5,2.09C10.91,3.81 9.24,3 7.5,3C4.42,3 2,5.42 2,8.5c0,3.78 3.4,6.86 8.55,11.54L12,21.35l1.45,-1.32C18.6,15.36 22,12.28 22,8.5C22,5.42 19.58,3 16.5,3zM12.1,18.55l-0.1,0.1l-0.1,-0.1C7.14,14.24 4,11.39 4,8.5C4,6.5 5.5,5 7.5,5c1.54,0 3.04,0.99 3.57,2.36h1.87C13.46,5.99 14.96,5 16.5,5c2,0 3.5,1.5 3.5,3.5c0,2.89 -3.14,5.74 -7.9,10.05z",
    )
    val Puzzle: ImageVector = icon(
        "Puzzle",
        "M20.5,11H19V7c0,-1.1 -0.9,-2 -2,-2h-4V3.5C13,2.12 11.88,1 10.5,1S8,2.12 8,3.5V5H4c-1.1,0 -1.99,0.9 -1.99,2v3.8H3.5c1.49,0 2.7,1.21 2.7,2.7s-1.21,2.7 -2.7,2.7H2V20c0,1.1 0.9,2 2,2h3.8v-1.5c0,-1.49 1.21,-2.7 2.7,-2.7c1.49,0 2.7,1.21 2.7,2.7V22H17c1.1,0 2,-0.9 2,-2v-4h1.5c1.38,0 2.5,-1.12 2.5,-2.5S21.88,11 20.5,11z",
    )
    val ArrowUp: ImageVector = icon("ArrowUp", "M7.41,15.41L12,10.83l4.59,4.58L18,14l-6,-6 -6,6z")
    val ArrowDown: ImageVector = icon("ArrowDown", "M7.41,8.59L12,13.17l4.59,-4.58L18,10l-6,6 -6,-6 1.41,-1.41z")
    val More: ImageVector = icon("More", "M6,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2zM18,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2zM12,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2z")
    val Sleep: ImageVector = icon("Sleep", "M12.34,2.02C6.59,1.82 2,6.42 2,12c0,5.52 4.48,10 10,10c3.71,0 6.93,-2.02 8.66,-5.02C13.15,16.73 8.57,8.55 12.34,2.02z")
    val Back: ImageVector = icon("Back", "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z")
    val Mic: ImageVector = icon(
        "Mic",
        "M12,14c1.66,0 2.99,-1.34 2.99,-3L15,5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66 1.34,3 3,3zM17.3,11c0,3 -2.54,5.1 -5.3,5.1S6.7,14 6.7,11H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72h-1.7z",
    )
}
