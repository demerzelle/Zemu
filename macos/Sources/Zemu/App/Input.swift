import AppKit
import GameController
import ZemuCore

/** What a key or controller button means, wherever it came from. */
enum InputAction: Equatable {
    case move(MoveDirection)
    case select
    case back
    /** X / O key: the focused item's options menu (in the player: cycle subtitles). */
    case secondary
    /** Y: Search (in the player: cycle audio). */
    case tertiary
    case prevSection, nextSection
    case scrubBack, scrubForward
    /** Start / ☰: options menu (in the player: play/pause). */
    case menu
    /** View / Select: Settings (in the player: Picture in Picture). */
    case view
}

enum InputSource { case keyboard, gamepad }

/**
 * Routes keyboard and gamepad input to whatever is on screen: the on-screen keyboard, an action
 * menu, a trailer, Picture in Picture, the player, or the main UI's focus engine.
 */
@MainActor
final class InputRouter {
    static let shared = InputRouter()

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var lastMouse: NSPoint?
    private var repeatTimer: Timer?
    private var heldAction: InputAction?
    private var stickDirection: MoveDirection?

    private var app: AppModel { AppModel.shared }
    private var fe: FocusEngine { FocusEngine.shared }

    func start() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if Screensaver.shared.keyInput(e) { return nil }
            return self.handleKey(e) ? nil : e
        }
        // Moving the mouse hands control back to the pointer: drop the focus ring.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            guard let self else { return e }
            let p = NSEvent.mouseLocation
            if let l = self.lastMouse, hypot(p.x - l.x, p.y - l.y) > 8, self.fe.focused != nil, self.app.actionMenu == nil, self.app.osk == nil {
                self.fe.clear()
            }
            self.lastMouse = p
            return e
        }
        startGamepads()
    }

    // MARK: Keyboard

    private func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        let window = e.window
        let editing = window?.firstResponder is NSText
        let inSheet = window != nil && window === PlayerWindow.host?.attachedSheet

        // Command palette: the field keeps typing; arrows choose, Return runs, Esc closes.
        if app.showPalette {
            switch e.keyCode {
            case 125: app.paletteMove(1); return true
            case 126: app.paletteMove(-1); return true
            case 36, 76: app.paletteRun(); return true
            case 53: app.showPalette = false; return true
            default: return false
            }
        }
        if app.showShortcuts, e.keyCode == 53 { app.showShortcuts = false; return true }

        // Typing: keys belong to the text field, except Esc (stop editing) and ↑/↓ (leave the field).
        if editing {
            switch e.keyCode {
            case 53:
                window?.makeFirstResponder(nil)
                return true
            case 125, 126:
                window?.makeFirstResponder(nil)
                route(.move(e.keyCode == 125 ? .down : .up), source: .keyboard, isRepeat: e.isARepeat)
                return true
            default: return false
            }
        }

        if let pip = window as? PiPPanel { return pip.handleKey(e) }

        if mods.contains(.command) {
            if e.charactersIgnoringModifiers == "s", let p = app.player { p.saveFrame(); return true }
            return false
        }
        if !mods.isEmpty { return false }

        // Player letter shortcuts.
        if let p = app.player, !app.pip, app.actionMenu == nil, app.osk == nil, app.trailer == nil, window === PlayerWindow.host,
           let c = e.charactersIgnoringModifiers?.lowercased(), playerLetter(c, p) {
            p.noteInteraction()
            return true
        }

        let action: InputAction?
        switch e.keyCode {
        case 123: action = .move(.left)
        case 124: action = .move(.right)
        case 125: action = .move(.down)
        case 126: action = .move(.up)
        case 36, 76: action = .select // return, keypad enter
        case 49: action = app.player != nil && !app.pip && app.actionMenu == nil ? nil : .select // space
        case 53: action = inSheet ? nil : .back // esc: sheets close themselves
        case 51: action = .back // delete
        default:
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "o": action = .secondary
            default: action = nil
            }
        }

        // Space in the player: play/pause.
        if e.keyCode == 49, let p = app.player, !app.pip, app.actionMenu == nil, app.osk == nil {
            p.togglePlay()
            p.showControls()
            return true
        }
        guard let action else { return false }
        // Return in a sheet with nothing focused belongs to its default button.
        if inSheet && action == .select && !(fe.focusedIsValid && fe.focused?.anchor?.window === window) { return false }
        return route(action, source: .keyboard, isRepeat: e.isARepeat)
    }

    private func playerLetter(_ c: String, _ p: PlayerModel) -> Bool {
        switch c {
        case "k": p.togglePlay()
        case "j": p.seekBy(-10_000)
        case "l": p.seekBy(10_000)
        case "f": PlayerWindow.toggleFullScreen()
        case "m": p.toggleMute(); p.flash(p.muted ? "Muted" : "Sound on")
        case "s": p.cycleSubtitles()
        case "a": p.cycleAudio()
        case "c": p.subtitleStyleOpen.toggle(); p.showControls()
        case "n": p.playNextNow()
        case "t", "i": app.enterPiP()
        case "p": p.cycleAspect()
        case "z": p.adjustSubtitleDelay(-0.1)
        case "x": p.adjustSubtitleDelay(0.1)
        case "[": p.changeSpeed(max(0.25, p.speed - 0.25)); p.flash("Speed \(p.speedLabel)")
        case "]": p.changeSpeed(min(3, p.speed + 0.25)); p.flash("Speed \(p.speedLabel)")
        case "=": p.changeSpeed(1); p.flash("Speed normal")
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": p.seek(toFraction: Double(Int(c)!) / 10)
        default: return false
        }
        return true
    }

    // MARK: Routing

    @discardableResult
    func route(_ action: InputAction, source: InputSource, isRepeat: Bool = false) -> Bool {
        // Sound effects only when something happens (focus actually moved, something was chosen).
        let before = fe.focused
        let handled = routeAction(action, source: source, isRepeat: isRepeat)
        if handled, app.player == nil || app.pip {
            switch action {
            case .move: if fe.focused !== before { SoundFx.play(.move) }
            case .select: SoundFx.play(.select)
            case .back: SoundFx.play(.back)
            case .secondary, .menu: SoundFx.play(.hold)
            default: break
            }
        }
        return handled
    }

    private func routeAction(_ action: InputAction, source: InputSource, isRepeat: Bool) -> Bool {
        if case .move = action { NSCursor.setHiddenUntilMouseMoves(true) }

        if let osk = app.osk {
            switch action {
            case .move(let d): fe.move(d, scope: "osk")
            case .select: fe.activate(scope: "osk", fromGamepad: false)
            case .back: app.osk = nil
            case .secondary: if !osk.text.wrappedValue.isEmpty { osk.text.wrappedValue.removeLast() }
            case .tertiary: osk.text.wrappedValue.append(" ")
            case .menu: app.osk = nil; osk.onSubmit?()
            default: break
            }
            return true
        }
        if app.actionMenu != nil {
            switch action {
            case .move(let d): fe.move(d, scope: "menu")
            case .select: fe.activate(scope: "menu", fromGamepad: false)
            case .back, .secondary, .menu: app.actionMenu = nil
            default: break
            }
            return true
        }
        if app.trailer != nil {
            switch action {
            case .back, .select: app.trailer = nil; return true
            case .move: fe.move(action.direction!, scope: "trailer"); return true
            default: return false
            }
        }
        if let p = app.player, !app.pip { return routePlayer(action, p, source: source, isRepeat: isRepeat) }
        return routeMain(action, source: source)
    }

    private func routeMain(_ action: InputAction, source: InputSource) -> Bool {
        switch action {
        case .move(let d):
            if app.picking { fe.move(d, scope: "main"); return true }
            fe.move(d, scope: "main")
        case .select:
            if !fe.activate(scope: "main", fromGamepad: source == .gamepad) { fe.focusInitial(scope: "main") }
        case .back:
            if let sheet = PlayerWindow.host?.attachedSheet {
                // Sheets close with their Cancel (Esc) button.
                if let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber,
                                              context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                    sheet.sendEvent(esc)
                }
            } else if !app.stack.isEmpty {
                app.back()
                fe.clear()
            } else if app.section != .home {
                app.go(.home)
            } else {
                return false
            }
        case .secondary, .menu:
            return fe.secondary(scope: "main")
        case .tertiary:
            app.go(.search)
        case .view:
            app.go(.settings)
        case .prevSection, .nextSection:
            let all = Section.allCases
            let i = all.firstIndex(of: app.section) ?? 1
            app.go(all[(i + (action == .nextSection ? 1 : all.count - 1)) % all.count])
            fe.clear()
        case .scrubBack, .scrubForward:
            return false
        }
        return true
    }

    private func routePlayer(_ action: InputAction, _ p: PlayerModel, source: InputSource, isRepeat: Bool) -> Bool {
        p.noteInteraction()
        let dialog = p.failure != nil || p.stillWatchingPrompt
        let menuMode = dialog || (p.controlsVisible && fe.focusedIsValid && fe.focused?.scope == "player")

        if menuMode {
            switch action {
            case .move(let d):
                let before = fe.focused
                fe.move(d, scope: "player", allowScroll: false)
                // Down past the button row hides the controls again.
                if d == .down && fe.focused === before && !dialog { p.hideControls() } else { p.showControls() }
            case .select:
                fe.activate(scope: "player", fromGamepad: false)
                p.showControls()
            case .back:
                if dialog { if p.failure != nil { p.close() } else { p.answerStillWatching(false) } }
                else { p.hideControls() }
            case .secondary: p.cycleSubtitles()
            case .tertiary: p.cycleAudio()
            case .menu: p.togglePlay()
            case .view: app.enterPiP()
            case .prevSection: p.seekBy(-10_000)
            case .nextSection: p.seekBy(10_000)
            case .scrubBack: p.scrub(-1, isRepeat: isRepeat)
            case .scrubForward: p.scrub(1, isRepeat: isRepeat)
            }
            return true
        }

        switch action {
        case .move(.left): p.scrub(-1, isRepeat: isRepeat)
        case .move(.right): p.scrub(1, isRepeat: isRepeat)
        case .move(let d):
            if source == .keyboard {
                p.setVolume(p.volume + (d == .up ? 5 : -5))
                p.flash("Volume \(Int(p.volume))%")
            } else {
                p.openControlsMenu()
            }
        case .select:
            if p.countdown != nil { p.playNextNow() }
            else if p.activeSegment != nil { p.skipSegment() }
            else {
                if source == .gamepad { p.togglePlay() }
                p.openControlsMenu()
            }
        case .back:
            if p.countdown != nil { p.cancelCountdown() }
            else if p.activeSegment != nil { p.dismissSegment() }
            else if PlayerWindow.isFullScreen && !PlayerWindow.enteredFullScreen && source == .keyboard { PlayerWindow.toggleFullScreen() }
            else { p.close() }
        case .secondary: p.cycleSubtitles()
        case .tertiary: p.cycleAudio()
        case .menu: p.togglePlay(); p.showControls()
        case .view: app.enterPiP()
        case .prevSection: p.seekBy(-10_000)
        case .nextSection: p.seekBy(10_000)
        case .scrubBack: p.scrub(-1, isRepeat: isRepeat)
        case .scrubForward: p.scrub(1, isRepeat: isRepeat)
        }
        return true
    }

    // MARK: Gamepads

    private func startGamepads() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            guard let c = n.object as? GCController else { return }
            MainActor.assumeIsolated {
                self?.configure(c)
                AppModel.shared.toast("🎮 \(c.vendorName ?? "Controller") connected")
            }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { n in
            let name = (n.object as? GCController)?.vendorName ?? "Controller"
            MainActor.assumeIsolated { AppModel.shared.toast("🎮 \(name) disconnected") }
        }
        GCController.controllers().forEach(configure)
        GCController.startWirelessControllerDiscovery {}
    }

    private func configure(_ c: GCController) {
        c.handlerQueue = .main
        if let g = c.extendedGamepad {
            bindDirections(g.dpad)
            g.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                MainActor.assumeIsolated { self?.stick(x: x, y: y) }
            }
            bind(g.buttonA, .select)
            bind(g.buttonB, .back)
            bind(g.buttonX, .secondary)
            bind(g.buttonY, .tertiary)
            bind(g.leftShoulder, .prevSection)
            bind(g.rightShoulder, .nextSection)
            bind(g.leftTrigger, .scrubBack, repeats: true)
            bind(g.rightTrigger, .scrubForward, repeats: true)
            bind(g.buttonMenu, .menu)
            if let o = g.buttonOptions { bind(o, .view) }
        } else if let m = c.microGamepad {
            bindDirections(m.dpad)
            bind(m.buttonA, .select)
            bind(m.buttonX, .back)
            bind(m.buttonMenu, .back)
        }
    }

    private func bindDirections(_ pad: GCControllerDirectionPad) {
        bind(pad.up, .move(.up), repeats: true)
        bind(pad.down, .move(.down), repeats: true)
        bind(pad.left, .move(.left), repeats: true)
        bind(pad.right, .move(.right), repeats: true)
    }

    private func bind(_ button: GCControllerButtonInput, _ action: InputAction, repeats: Bool = false) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                guard let self, NSApp.isActive else { return }
                if pressed { self.press(action, repeats: repeats) } else if self.heldAction == action { self.release() }
            }
        }
    }

    /** Fires now, then repeats while held (faster the longer it's held). */
    private func press(_ action: InputAction, repeats: Bool) {
        // Any button wakes the screensaver; A starts the title it shows.
        if Screensaver.shared.gamepadInput(play: action == .select) { return }
        release()
        route(action, source: .gamepad)
        guard repeats else { return }
        heldAction = action
        var count = 0
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.heldAction == action else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.heldAction == action else { return }
                        count += 1
                        self.route(action, source: .gamepad, isRepeat: true)
                    }
                }
            }
        }
    }

    private func release() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldAction = nil
    }

    private func stick(x: Float, y: Float) {
        let dir: MoveDirection?
        if abs(x) < 0.5 && abs(y) < 0.5 { dir = nil }
        else if abs(x) > abs(y) { dir = x > 0 ? .right : .left }
        else { dir = y > 0 ? .up : .down }
        guard dir != stickDirection else { return }
        stickDirection = dir
        if let dir { press(.move(dir), repeats: true) } else if case .move = heldAction { release() }
    }
}

extension InputAction {
    var direction: MoveDirection? { if case .move(let d) = self { return d }; return nil }
}
