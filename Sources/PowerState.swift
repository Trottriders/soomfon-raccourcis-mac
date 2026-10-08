import Foundation

enum DeckPowerEvent {
    case screensSleep, screensWake, systemSleep, systemWake
}

struct DeckPowerState {
    private(set) var screensSleeping = false
    private(set) var systemSleeping = false
    var sleeping: Bool { screensSleeping || systemSleeping }

    init(screensSleeping: Bool = false) { self.screensSleeping = screensSleeping }

    mutating func apply(_ event: DeckPowerEvent) {
        switch event {
        case .screensSleep: screensSleeping = true
        case .screensWake: screensSleeping = false
        case .systemSleep: systemSleeping = true
        case .systemWake: systemSleeping = false
        }
    }
}
