import AppKit
import ApplicationServices

enum ShortcutEmitter {
    static func events(for shortcut: Shortcut) -> [CGEvent]? {
        guard shortcut.isValid, let source = CGEventSource(stateID: .privateState) else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifiers))
        let modifiers: [(NSEvent.ModifierFlags, CGEventFlags, UInt16)] = [
            (.control, .maskControl, 59), (.option, .maskAlternate, 58),
            (.shift, .maskShift, 56), (.command, .maskCommand, 55)
        ].filter { flags.contains($0.0) }
        var active: CGEventFlags = []
        var events: [CGEvent] = []
        for (_, flag, code) in modifiers {
            active.insert(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return nil }
            event.type = .flagsChanged; event.flags = active
            events.append(event)
        }
        if !shortcut.isModifiersOnly {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return nil }
            down.flags = active; up.flags = active
            events += [down, up]
        }
        // Release every synthetic modifier, including Command after Command-Tab.
        for (_, flag, code) in modifiers.reversed() {
            active.remove(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return nil }
            event.type = .flagsChanged; event.flags = active
            events.append(event)
        }
        return events
    }
}

struct KeyboardEventSpec: Equatable {
    var code: UInt16
    var down: Bool
    var flags: CGEventFlags
    var modifier: Bool = false
}
struct HeldKeyboardState {
    var holds: [UUID: Shortcut] = [:]
    static let modifiers: [(NSEvent.ModifierFlags, CGEventFlags, UInt16)] = [
        (.control, .maskControl, 59), (.option, .maskAlternate, 58),
        (.shift, .maskShift, 56), (.command, .maskCommand, 55)
    ]
    var keyCodes: Set<UInt16> { Set(holds.values.filter { !$0.isModifiersOnly }.map(\.keyCode)) }
    var flags: CGEventFlags {
        var result: CGEventFlags = []
        for shortcut in holds.values {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifiers))
            for (ns, cg, _) in Self.modifiers where flags.contains(ns) { result.insert(cg) }
        }
        return result
    }
    func transition(to next: HeldKeyboardState) -> [KeyboardEventSpec] {
        var events: [KeyboardEventSpec] = []
        var active = flags
        for code in keyCodes.subtracting(next.keyCodes).sorted() {
            events.append(KeyboardEventSpec(code: code, down: false, flags: active))
        }
        for (_, flag, code) in Self.modifiers.reversed() where active.contains(flag) && !next.flags.contains(flag) {
            active.remove(flag); events.append(KeyboardEventSpec(code: code, down: false, flags: active, modifier: true))
        }
        for (_, flag, code) in Self.modifiers where !active.contains(flag) && next.flags.contains(flag) {
            active.insert(flag); events.append(KeyboardEventSpec(code: code, down: true, flags: active, modifier: true))
        }
        for code in next.keyCodes.subtracting(keyCodes).sorted() {
            events.append(KeyboardEventSpec(code: code, down: true, flags: active))
        }
        return events
    }
}

@MainActor final class HeldKeyboard {
    private var state = HeldKeyboardState()
    var isHolding: Bool { !state.holds.isEmpty }
    private func apply(_ next: HeldKeyboardState) -> Bool {
        let specs = state.transition(to: next)
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        var events: [CGEvent] = []
        for spec in specs {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: spec.code, keyDown: spec.down) else { return false }
            if spec.modifier { event.type = .flagsChanged }
            event.flags = spec.flags; events.append(event)
        }
        state = next
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }
    func begin(_ shortcut: Shortcut, token: UUID) -> Bool {
        guard shortcut.isValid else { return false }
        var next = state; next.holds[token] = shortcut; return apply(next)
    }
    func end(_ token: UUID) { var next = state; next.holds.removeValue(forKey: token); _ = apply(next) }
    func tap(_ shortcut: Shortcut) -> Bool {
        let token = UUID(); guard begin(shortcut, token: token) else { return false }
        end(token); return true
    }
    func releaseAll() { guard isHolding else { return }; _ = apply(HeldKeyboardState()) }
}
