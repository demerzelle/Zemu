package com.zemu.tv.ui

import com.zemu.tv.data.officialTrailers
import com.zemu.tv.ui.theme.appBackground
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import com.zemu.tv.ui.components.Haptics
import kotlin.math.abs
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.zemu.tv.R
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.navArgument
import com.zemu.tv.container
import com.zemu.tv.app
import com.zemu.tv.data.trailerId
import com.zemu.tv.player.TrailerActivity
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.CardAction
import com.zemu.tv.ui.components.CardMenuDialog
import com.zemu.tv.ui.components.FocusScrollMargins
import com.zemu.tv.ui.components.LocalCardMenu
import com.zemu.tv.ui.components.LocalWatched
import com.zemu.tv.ui.components.cardActions
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import com.zemu.tv.data.Meta
import com.zemu.tv.ui.addons.AddonBrowserScreen
import com.zemu.tv.ui.browse.BrowseScreen
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.details.DetailsScreen
import com.zemu.tv.ui.home.HomeScreen
import com.zemu.tv.ui.mylist.MyListScreen
import com.zemu.tv.ui.person.PersonScreen
import com.zemu.tv.ui.search.SearchScreen
import com.zemu.tv.ui.settings.SettingsScreen
import com.zemu.tv.ui.theme.Palette

/** [bottom] items sit in the menu's bottom left and open dialogs instead of pages. */
private enum class Dest(val route: String, val label: String, val icon: ImageVector, val bottom: Boolean = false) {
    SEARCH("search", "Search", Icons.Filled.Search),
    HOME("home", "Home", Icons.Filled.Home),
    MOVIES("movies", "Movies", AppIcons.Movie),
    SERIES("series", "Series", AppIcons.Tv),
    ANIME("anime", "Anime", AppIcons.Anime),
    MY_LIST("mylist", "My List", Icons.Filled.Favorite),
    SETTINGS("settings", "Settings", Icons.Filled.Settings),
    PROFILES("@profiles", "Profiles", Icons.Filled.Person, bottom = true),
    /** Kid profiles only: the kid picks their own theme. */
    THEME("@theme", "Theme", AppIcons.Palette, bottom = true),
}

private val RAIL_WIDTH = 76.dp
private val RAIL_OPEN_WIDTH = 210.dp

fun detailsRoute(m: Meta, section: String = "", play: Boolean = false) =
    "details/${Uri.encode(m.type)}/${Uri.encode(m.id)}?section=$section&play=$play"

@Composable
fun AppShell() {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val current = route
    val showRail = route != null && !route.startsWith("details") && !route.startsWith("person") && !route.startsWith("browse") && !route.startsWith("services") && !route.startsWith("rows/")
    val context = LocalContext.current
    val c = context.container
    // With Instant play on, selecting a title starts it; the long-press menu's "Details" still opens the page.
    val scope = rememberCoroutineScope()
    val open: (Meta) -> Unit = { m ->
        resolving(context, scope, m) { nav.navigate(detailsRoute(it, play = c.userStore.settings.value.instantPlay)) }
    }
    val watched by c.userStore.watched.collectAsStateWithLifecycle()
    val myList by c.userStore.myList.collectAsStateWithLifecycle()
    val history by c.userStore.history.collectAsStateWithLifecycle()
    var menuFor by remember { mutableStateOf<Meta?>(null) }
    var menuRowOptions by remember { mutableStateOf<(() -> Unit)?>(null) }
    var railOpen by remember { mutableStateOf(false) }
    val kids = com.zemu.tv.ui.kids.rememberKids()
    val switchProfile = com.zemu.tv.LocalSwitchProfile.current
    // Bottom-left menu dialogs: a kid's theme picker, and the parent code to leave a kid profile.
    var kidsTheme by remember { mutableStateOf(false) }
    var parentCheck by remember { mutableStateOf(false) }
    LaunchedEffect(showRail) { if (!showRail) railOpen = false }
    // A movie just finished: back to Home.
    val goHome = com.zemu.tv.PendingOpen.goHome
    LaunchedEffect(goHome) {
        if (!goHome) return@LaunchedEffect
        com.zemu.tv.PendingOpen.goHome = false
        nav.popBackStack("home", inclusive = false)
    }
    val pending = com.zemu.tv.PendingOpen.target
    LaunchedEffect(pending) {
        val (type, id) = pending ?: return@LaunchedEffect
        val play = com.zemu.tv.PendingOpen.play
        com.zemu.tv.PendingOpen.target = null
        com.zemu.tv.PendingOpen.play = false
        nav.navigate(detailsRoute(Meta(id = id, type = type), play = play))
    }

    CompositionLocalProvider(LocalCardMenu provides { m, rowOptions -> menuRowOptions = rowOptions; menuFor = m }, LocalWatched provides watched) {
    FocusScrollMargins {
    Box(Modifier.fillMaxSize()) {
        StyleBackdrop(Modifier.fillMaxSize())
        NavHost(
            navController = nav,
            startDestination = "home",
            modifier = Modifier.fillMaxSize().padding(start = if (showRail) RAIL_WIDTH else 0.dp)
                // Cat Rave: the whole interface bounces and sways to the beat.
                .then(
                    if (com.zemu.tv.ui.theme.Palette.Style != com.zemu.tv.ui.theme.UiStyle.CATRAVE) Modifier
                    else Modifier.graphicsLayer {
                        val t = com.zemu.tv.ui.theme.RaveClock.t
                        scaleX = 1f + 0.015f * (1f - (t * 2.13f) % 1f); scaleY = scaleX
                        rotationZ = kotlin.math.sin(t * 1.6f) * 0.8f
                    },
                ),
        ) {
            val browse: (com.zemu.tv.ui.home.BrowseTarget) -> Unit = { t ->
                nav.navigate("browse/${t.type}?service=${Uri.encode(t.service.orEmpty())}&label=${Uri.encode(t.serviceLabel.orEmpty())}&studio=${t.studio.orEmpty()}")
            }
            val allServices: (String) -> Unit = { type -> nav.navigate("services/$type") }
            composable("home") {
                HomeScreen(onOpen = open, onOpenSettings = { nav.navigateTop("addons") }, onPlay = { m -> resolving(context, scope, m) { nav.navigate(detailsRoute(it, play = true)) } }, onBrowse = browse, onAllServices = allServices, onSearch = { nav.navigateTop("search") })
            }
            listOf("movies" to "movie", "series" to "series", "anime" to "anime").forEach { (route, page) ->
                composable(route) {
                    HomeScreen(onOpen = open, onOpenSettings = { nav.navigateTop("addons") }, onPlay = { m -> resolving(context, scope, m) { nav.navigate(detailsRoute(it, play = true)) } }, page = page, onBrowse = browse, onAllServices = allServices)
                }
            }
            composable(
                "browse/{type}?service={service}&label={label}&studio={studio}",
                arguments = listOf(navArgument("service") { defaultValue = "" }, navArgument("label") { defaultValue = "" }, navArgument("studio") { defaultValue = "" }),
            ) { e ->
                BrowseScreen(
                    type = e.arguments?.getString("type") ?: "movie",
                    onOpen = open,
                    service = e.arguments?.getString("service")?.ifEmpty { null },
                    studio = e.arguments?.getString("studio")?.ifEmpty { null },
                    serviceLabel = e.arguments?.getString("label")?.ifEmpty { null },
                )
            }
            composable("services/{type}") { e -> com.zemu.tv.ui.browse.ServicesScreen(e.arguments?.getString("type") ?: "movie", onBrowse = browse) }
            composable("search") { SearchScreen(onOpen = open) }
            composable("mylist") { MyListScreen(onOpen = open) }
            composable("settings") { com.zemu.tv.ui.kids.ParentLock { SettingsScreen(onOpenAddons = { nav.navigate("addons") }, onOpenServices = { nav.navigate("services/movie") }, onManageRows = { nav.navigate("rows/$it") }) } }
            composable("rows/{page}") { e -> com.zemu.tv.ui.kids.ParentLock { com.zemu.tv.ui.settings.RowsManagerScreen(e.arguments?.getString("page") ?: "home") } }
            composable("addons") { com.zemu.tv.ui.kids.ParentLock { AddonBrowserScreen() } }
            composable("person/{key}") { e -> PersonScreen(key = Uri.decode(e.arguments?.getString("key").orEmpty()), onOpen = open) }
            composable(
                "details/{type}/{id}?section={section}&play={play}",
                arguments = listOf(
                    navArgument("section") { defaultValue = "" },
                    navArgument("play") { type = NavType.BoolType; defaultValue = false },
                ),
            ) { e ->
                // Kids Mode: titles above the allowed rating stop here, however they were opened.
                com.zemu.tv.ui.kids.KidsTitleGate(e.arguments?.getString("type") ?: "movie", e.arguments?.getString("id").orEmpty()) {
                DetailsScreen(
                    type = e.arguments?.getString("type") ?: "movie",
                    id = e.arguments?.getString("id").orEmpty(),
                    section = e.arguments?.getString("section").orEmpty(),
                    autoPlay = e.arguments?.getBoolean("play") == true,
                    // After an instant start, Back from the player returns to where the title was picked.
                    onAutoPlayed = { nav.popBackStack() },
                    onOpen = open,
                    onOpenSettings = { nav.navigateTop("addons") },
                    onOpenPerson = { key -> nav.navigate("person/${Uri.encode(key)}") },
                )
                }
            }
        }
        if (showRail) {
            // Touch-opened menu: dim the page; tapping it closes the menu.
            if (railOpen) Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f))
                    .pointerInput(Unit) { detectTapGestures { railOpen = false } },
            )
            NavRail(current, railOpen, kids.on, onTouchOpen = { railOpen = it }) { d ->
                railOpen = false
                when {
                    d == Dest.THEME -> kidsTheme = true
                    d == Dest.PROFILES -> if (kids.on) parentCheck = true else switchProfile()
                    else -> {
                        if (d.route != current) Haptics.buzz(context)
                        nav.navigateTop(d.route)
                    }
                }
            }
        }
    }
    if (kidsTheme) com.zemu.tv.ui.kids.KidsThemePicker { kidsTheme = false }
    if (parentCheck) com.zemu.tv.ui.kids.ParentCheck("Leave this kid profile?", onDismiss = { parentCheck = false }) {
        parentCheck = false
        switchProfile()
    }
    menuFor?.let { m ->
        CardMenuDialog(
            meta = m,
            actions = cardActions(
                m,
                watched = m.id in watched,
                inMyList = myList.any { it.id == m.id },
                inHistory = history.any { it.meta.id == m.id },
                rowOptions = menuRowOptions != null,
            ).filter { it != CardAction.TRAILER || c.userStore.settings.value.trailers },
            onAction = { a -> resolving(context, scope, m) { m ->
                when (a) {
                    CardAction.PLAY -> if (kids.on || !com.zemu.tv.player.Playback.resumeSaved(context, m)) nav.navigate(detailsRoute(m, play = true))
                    CardAction.DETAILS -> nav.navigate(detailsRoute(m))
                    CardAction.EPISODES -> nav.navigate(detailsRoute(m, "episodes"))
                    CardAction.TRAILER -> m.officialTrailers.takeIf { it.isNotEmpty() }?.let { TrailerActivity.start(context, it) }
                    CardAction.MY_LIST_ADD, CardAction.MY_LIST_REMOVE -> scope.launch { c.userStore.toggleMyList(m) }
                    CardAction.MARK_WATCHED -> scope.launch { c.userStore.setWatched(m, true) }
                    CardAction.MARK_UNWATCHED -> scope.launch { c.userStore.setWatched(m, false) }
                    CardAction.REMOVE_HISTORY -> scope.launch { c.userStore.removeFromHistory(m.id) }
                    CardAction.ROW_OPTIONS -> menuRowOptions?.invoke()
                }
            } },
            onDismiss = { menuFor = null },
        )
    }
    }
    }
}

/** The page's background plus the whole-app style's animated scene (PS2 towers, kids' sky, …). */
@Composable
private fun StyleBackdrop(modifier: Modifier) = Box(modifier.appBackground()) {
    when (com.zemu.tv.ui.theme.Palette.Style) {
        com.zemu.tv.ui.theme.UiStyle.PS2 -> com.zemu.tv.ui.theme.Ps2Backdrop()
        com.zemu.tv.ui.theme.UiStyle.ACID -> com.zemu.tv.ui.theme.AcidBackdrop()
        com.zemu.tv.ui.theme.UiStyle.ETHEREAL -> com.zemu.tv.ui.theme.EtherealBackdrop()
        com.zemu.tv.ui.theme.UiStyle.RETRO -> com.zemu.tv.ui.theme.RetroBackdrop(com.zemu.tv.ui.theme.Palette.colors.variant)
        com.zemu.tv.ui.theme.UiStyle.GRAFFITI -> com.zemu.tv.ui.theme.GraffitiBackdrop()
        com.zemu.tv.ui.theme.UiStyle.LIQUID -> com.zemu.tv.ui.theme.LiquidBackdrop()
        com.zemu.tv.ui.theme.UiStyle.CATRAVE -> com.zemu.tv.ui.theme.CatRaveBackdrop()
        com.zemu.tv.ui.theme.UiStyle.TODDLER -> com.zemu.tv.ui.theme.ToddlerBackdrop()
        com.zemu.tv.ui.theme.UiStyle.GRADE -> com.zemu.tv.ui.theme.GradeSchoolBackdrop()
        com.zemu.tv.ui.theme.UiStyle.TEEN -> com.zemu.tv.ui.theme.YoungAdultBackdrop()
        else -> {}
    }
}

private fun NavHostController.navigateTop(route: String) = navigate(route) {
    popUpTo("home") { saveState = true }
    launchSingleTop = true
    restoreState = true
}

/**
 * Left menu. With a remote it expands with labels while it has focus. On touch screens the labels
 * stay hidden: tap an icon to change page, or hold and slide over the icons to switch pages as you
 * go (the icons don't scroll). Drag right on the menu, or tap the logo or an empty spot, to show
 * the labels; tapping outside hides them again ([touchOpen]).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun NavRail(current: String?, touchOpen: Boolean, kidsOn: Boolean, onTouchOpen: (Boolean) -> Unit, onSelect: (Dest) -> Unit) {
    var hasFocus by remember { mutableStateOf(false) }
    val usingRemote = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val expanded = (hasFocus && usingRemote) || touchOpen
    val width by animateDpAsState(if (expanded) RAIL_OPEN_WIDTH else RAIL_WIDTH, label = "rail")
    // Labels fade in as the menu widens, so nothing pokes out past its edge mid-animation.
    val progress = ((width - RAIL_WIDTH) / (RAIL_OPEN_WIDTH - RAIL_WIDTH)).coerceIn(0f, 1f)
    // Settings is for grown-ups; in Kids Mode it's off the menu.
    val main = Dest.entries.filter { !it.bottom && !(kidsOn && it == Dest.SETTINGS) }
    val bottom = Dest.entries.filter { it.bottom && (kidsOn || it != Dest.THEME) }
    val screenWidth = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp.dp
    val requesters = remember { Dest.entries.associateWith { FocusRequester() } }
    val selected = Dest.entries.firstOrNull { it.route == current }
    // Ten quick presses on the logo unlock something.
    val ctx = LocalContext.current
    val logoScope = rememberCoroutineScope()
    var logoTaps by remember { mutableStateOf(0) }
    var lastLogoTap by remember { mutableStateOf(0L) }
    var logoFocused by remember { mutableStateOf(false) }
    // Stable across recompositions (it only touches remembered state), so the touch handler can keep it.
    val onLogo: () -> Unit = remember { {
        val now = System.currentTimeMillis()
        if (now - lastLogoTap > 3_000) logoTaps = 0
        lastLogoTap = now
        logoTaps++
        when {
            logoTaps >= 10 -> {
                logoTaps = 0
                logoScope.launch { ctx.container.userStore.updateSettings { it.copy(catRaveUnlocked = true, dynamicTheme = "CATRAVE", themeBeforeRave = if (it.dynamicTheme == "CATRAVE") it.themeBeforeRave else it.dynamicTheme) } }
                android.widget.Toast.makeText(ctx, "😼  CAT RAVE UNLOCKED  😼", android.widget.Toast.LENGTH_LONG).show()
            }
            logoTaps >= 7 -> android.widget.Toast.makeText(ctx, "${10 - logoTaps}…", android.widget.Toast.LENGTH_SHORT).show()
        }
    } }
    // Where each icon is on screen, for working out which one a finger is over.
    val bounds = remember { mutableStateMapOf<Dest, Rect>() }
    var railOrigin by remember { mutableStateOf(Offset.Zero) }
    val latestCurrent by rememberUpdatedState(current)
    val latestOpen by rememberUpdatedState(touchOpen)
    val select by rememberUpdatedState(onSelect)
    val setOpen by rememberUpdatedState(onTouchOpen)

    // A soft shadow rides the menu's edge while it's open, so the page fades out at the same width.
    if (progress > 0f) Box(
        Modifier
            .fillMaxHeight()
            .padding(start = width)
            .width(120.dp)
            .graphicsLayer { alpha = progress }
            .background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(Palette.Background.copy(alpha = 0.85f), Color.Transparent))),
    )
    androidx.compose.foundation.layout.BoxWithConstraints(
        Modifier
            .fillMaxHeight()
            .width(width)
            .clipToBounds()
            .onGloballyPositioned { railOrigin = it.positionInWindow() }
            .pointerInput(Unit) {
                fun destAt(p: Offset): Dest? = (p + railOrigin).let { w -> bounds.entries.firstOrNull { it.value.contains(w) }?.key }
                val slop = viewConfiguration.touchSlop
                awaitEachGesture {
                    // Initial pass: handle touches here, before the scrollable column underneath.
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    val start = down.position
                    var mode = 0 // 0 = undecided (a tap so far), 1 = sliding over icons, 2 = horizontal drag
                    var over = destAt(start)
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        // The lift position counts too, so a quick slide still lands on the icon under the finger.
                        val d = change.position - start
                        if (mode == 0 && (abs(d.x) > slop || abs(d.y) > slop)) {
                            mode = if (abs(d.x) > abs(d.y)) 2 else 1
                            if (mode == 1) over?.let { if (it.route != latestCurrent) select(it) }
                        }
                        if (mode != 0) change.consume()
                        when (mode) {
                            1 -> destAt(change.position)?.let { if (it != over) { over = it; select(it) } }
                            2 -> if (d.x > 40.dp.toPx()) setOpen(true) else if (d.x < -40.dp.toPx()) setOpen(false)
                        }
                        if (!change.pressed) break
                    }
                    if (mode == 0) {
                        val tapped = destAt(start)
                        when {
                            // Taps on the logo count toward the secret instead of opening the menu.
                            start.y < 64.dp.toPx() -> onLogo()
                            tapped != null -> { setOpen(false); select(tapped) }
                            else -> setOpen(!latestOpen)
                        }
                    }
                }
            },
    ) {
        // The menu's underlay is the page's own background scene, cut to the menu's width, so it looks
        // the same at any width instead of the page's posters showing through as it opens.
        val styled = Palette.Style != com.zemu.tv.ui.theme.UiStyle.NORMAL
        if (styled || Palette.Glass) StyleBackdrop(
            Modifier.fillMaxHeight().wrapContentWidth(Alignment.Start, unbounded = true).requiredWidth(screenWidth),
        )
        Box(Modifier.matchParentSize().background(Palette.Background.copy(alpha = if (Palette.Glass) 0.55f else if (styled) 0.8f else 1f)))
        Image(
            painter = painterResource(if (expanded) R.drawable.logo_wordmark else R.drawable.logo_mark),
            contentDescription = "Zemu",
            contentScale = ContentScale.Fit,
            alignment = Alignment.CenterStart,
            // The logo follows the theme's accent color.
            colorFilter = ColorFilter.tint(Palette.Accent),
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 20.dp, top = 22.dp, end = 16.dp)
                .height(if (expanded) 30.dp else 26.dp)
                .width(if (expanded) 170.dp else 36.dp)
                // Up from the top of the menu reaches the logo; OK (or a tap) presses it.
                .onFocusChanged { logoFocused = it.isFocused }
                .graphicsLayer { if (logoFocused) { scaleX = 1.15f; scaleY = 1.15f } }
                .clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = onLogo),
        )
        // Main pages centered as before; Profiles and Kids Mode in the bottom left. Item heights are fixed
        // (40dp + 2dp gap), so the gaps are worked out here and the whole menu still scrolls on short screens.
        val itemH = 42.dp
        val top = maxOf(64.dp, (maxHeight - itemH * main.size) / 2)
        val gap = maxOf(16.dp, maxHeight - top - itemH * (main.size + bottom.size) - 16.dp)
        Column(
            Modifier
                .fillMaxSize()
                .onFocusChanged { hasFocus = it.hasFocus }
                // Entering the menu always lands on the current page, not whichever item is nearest.
                .focusProperties { enter = { selected?.let { requesters.getValue(it) } ?: FocusRequester.Default } }
                .focusGroup()
                .verticalScroll(rememberScrollState())
                .padding(start = 12.dp, end = 12.dp, top = top, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            (main + bottom).forEach { d ->
                if (d == bottom.first()) Spacer(Modifier.height(gap - 2.dp))
                val isCurrent = current == d.route
                // A kid profile's way out is locked.
                val label = d.label
                val icon = if (d == Dest.PROFILES && kidsOn) Icons.Filled.Lock else d.icon
                val shape = RoundedCornerShape(10.dp)
                // Plain TV surface: remote only. Touch is handled by the rail above.
                Surface(
                    onClick = { onSelect(d) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(requesters.getValue(d))
                        .onGloballyPositioned { bounds[d] = it.boundsInWindow() },
                    shape = ClickableSurfaceDefaults.shape(shape = shape),
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.03f),
                    colors = ClickableSurfaceDefaults.colors(
                        containerColor = Color.Transparent,
                        contentColor = Palette.Text,
                        focusedContainerColor = Palette.Focus,
                        focusedContentColor = Palette.OnFocus,
                    ),
                ) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            icon,
                            contentDescription = label,
                            modifier = Modifier.size(22.dp),
                            tint = if (isCurrent && !expanded) Palette.Accent else androidx.tv.material3.LocalContentColor.current,
                        )
                        if (expanded) {
                            Spacer(Modifier.width(16.dp))
                            Text(
                                label, fontSize = 16.sp, fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Normal,
                                maxLines = 1, softWrap = false, modifier = Modifier.graphicsLayer { alpha = progress },
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Streaming service and studio rows list TMDB titles ("tmdb:movie:123"); they're looked up as
 * IMDb titles when opened, so the rest of the app only ever sees IMDb / Kitsu ids.
 */
private fun resolving(context: android.content.Context, scope: kotlinx.coroutines.CoroutineScope, m: Meta, block: (Meta) -> Unit) {
    if (!m.id.startsWith("tmdb:")) return block(m)
    scope.launch {
        val imdb = runCatching { context.container.tmdb.imdbFor(m.id) }.getOrNull()
        if (imdb == null) android.widget.Toast.makeText(context, "Couldn't find ${m.name ?: "this title"} in the catalog", android.widget.Toast.LENGTH_SHORT).show()
        else block(m.copy(id = imdb))
    }
}
