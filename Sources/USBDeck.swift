import Foundation
import IOKit.hid
import OSLog

struct PendingDeckDisplay {
    var images: [Int: Data] = [:]
    var brightness = 75
    var reinitialize = false
    mutating func merge(images: [(Int, Data)], brightness: Int, reinitialize: Bool) {
        for (index, image) in images { self.images[index] = image }
        self.brightness = brightness
        self.reinitialize = self.reinitialize || reinitialize
    }
}

struct DeckRetryState {
    private(set) var failures = 0
    private(set) var nextAttempt: TimeInterval = 0
    func canAttempt(at uptime: TimeInterval) -> Bool { uptime >= nextAttempt }
    mutating func failed(at uptime: TimeInterval) {
        failures = min(6, failures + 1)
        nextAttempt = uptime + min(30, pow(2, Double(failures - 1)))
    }
    mutating func succeeded() { failures = 0; nextAttempt = 0 }
}

final class USBDeck: @unchecked Sendable {
    var onStatus: ((Bool, String) -> Void)?
    var onReport: (([UInt8]) -> Void)?
    var onReady: (() -> Void)?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var loop: CFRunLoop?
    private let lock = NSLock()
    private var worker: Thread?
    private var timer: Timer?
    // Producer/worker state, protected by lock.
    private var stopped = false
    private var suspended = false
    private var displaySleeping = false
    private var reconnectRequested = false
    private var generation: UInt64 = 0
    private var pendingDisplay: PendingDeckDisplay?
    // Everything below is confined to the HID worker.
    private var initialized = false
    private var displayBlanked = false
    private var resetNeeded = false
    private var retry = DeckRetryState()
    private var lastStatus: (Bool, String)?
    private var lastHeartbeat: TimeInterval = 0
    private var lastCommitLog: TimeInterval = 0
    private var commits = 0
    private let logger = Logger(subsystem: "fr.local.soomfon-raccourcis", category: "USB")

    func start() {
        guard worker == nil else { return }
        worker = Thread { [self] in run() }
        worker?.name = "Soomfon USB"
        worker?.start()
    }

    private var currentGeneration: UInt64 {
        lock.lock(); defer { lock.unlock() }; return generation
    }
    private func advanceGeneration() {
        lock.lock(); generation &+= 1; lock.unlock()
        lastStatus = nil
    }
    private func status(_ connected: Bool, _ message: String) {
        if let previous = lastStatus, previous.0 == connected, previous.1 == message { return }
        lastStatus = (connected, message)
        let session = currentGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration == session else { return }
            self.onStatus?(connected, message)
        }
    }

    private func run() {
        let current = CFRunLoopGetCurrent()!
        lock.lock(); loop = current; lock.unlock()
        // A repeating pump cannot remain latched waiting for a one-shot display block.
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            autoreleasepool { self?.service() }
        }
        RunLoop.current.add(timer!, forMode: .default)
        configureManager()
        CFRunLoopRun()
        timer?.invalidate()
        closeSession()
        lock.lock(); loop = nil; pendingDisplay = nil; lock.unlock()
    }

    private func configureManager() {
        guard let loop else { return }
        status(false, "Recherche du boîtier — reconnexion automatique")
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: DeckProtocol.vendor,
                                        kIOHIDProductIDKey: DeckProtocol.product,
                                        kIOHIDPrimaryUsagePageKey: DeckProtocol.usagePage,
                                        kIOHIDPrimaryUsageKey: 1] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, d in
            guard let context else { return }
            Unmanaged<USBDeck>.fromOpaque(context).takeUnretainedValue().connect(d)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, d in
            guard let context else { return }
            let owner = Unmanaged<USBDeck>.fromOpaque(context).takeUnretainedValue()
            if owner.device == d {
                owner.disconnect()
                owner.status(false, "Boîtier débranché — reconnexion automatique")
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(m, loop, CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess { failed(result, operation: "ouverture USB") }
        else { logger.info("Session USB ouverte") }
    }

    private func closeSession() {
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            if let loop { IOHIDManagerUnscheduleFromRunLoop(manager, loop, CFRunLoopMode.defaultMode.rawValue) }
        }
        disconnect()
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }

    private func service() {
        lock.lock()
        let shouldStop = stopped, isSuspended = suspended, shouldBlank = displaySleeping
        let repair = reconnectRequested && !isSuspended
        if repair { reconnectRequested = false }
        lock.unlock()
        if shouldStop { CFRunLoopStop(CFRunLoopGetCurrent()); return }
        if isSuspended {
            if device != nil, !displayBlanked, !resetNeeded { blankDisplay() }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if repair { resetNeeded = true; retry.succeeded() }
        if resetNeeded && retry.canAttempt(at: now) {
            logger.info("Reconstruction de la connexion USB")
            closeSession()
            lock.lock(); pendingDisplay = nil; lock.unlock()
            resetNeeded = false
            configureManager()
        }
        guard !resetNeeded else { return }
        if device == nil && retry.canAttempt(at: now) {
            if let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let candidate = devices.first {
                connect(candidate)
            }
            if device == nil && !resetNeeded { retry.failed(at: now) }
        }
        guard device != nil, !resetNeeded else { return }
        if shouldBlank {
            if !displayBlanked { blankDisplay() }
            return
        }
        if displayBlanked { initialized = false; displayBlanked = false }
        drainDisplay()
        if initialized && !resetNeeded && now - lastHeartbeat >= 3 {
            lastHeartbeat = now
            _ = send(DeckProtocol.command("CONNECT"))
        }
    }

    private func connect(_ d: IOHIDDevice) {
        lock.lock(); let unavailable = suspended || stopped; lock.unlock()
        guard !unavailable, device == nil else { return }
        let result = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { failed(result, operation: "ouverture du boîtier"); return }
        device = d
        advanceGeneration()
        let b = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
        b.initialize(repeating: 0, count: 512)
        buffer = b
        IOHIDDeviceRegisterInputReportCallback(d, b, 512, { context, result, _, _, _, bytes, count in
            guard let context else { return }
            let owner = Unmanaged<USBDeck>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else { owner.failed(result, operation: "lecture USB"); return }
            guard count > 0 else { return }
            let report = Array(UnsafeBufferPointer(start: bytes, count: count))
            let session = owner.currentGeneration
            DispatchQueue.main.async { [weak owner] in
                guard let owner, owner.currentGeneration == session else { return }
                owner.onReport?(report)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        logger.info("Boîtier ouvert")
        status(true, "Soomfon connecté · 15 touches")
        let session = currentGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentGeneration == session else { return }
            self.onReady?()
        }
    }

    private func disconnect() {
        advanceGeneration()
        if let d = device {
            if let b = buffer { IOHIDDeviceRegisterInputReportCallback(d, b, 512, nil, nil) }
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil; initialized = false; displayBlanked = false
        buffer?.deinitialize(count: 512); buffer?.deallocate(); buffer = nil
    }

    private func failed(_ result: IOReturn, operation: String) {
        initialized = false; resetNeeded = true
        retry.failed(at: ProcessInfo.processInfo.systemUptime)
        logger.error("\(operation, privacy: .public) : \(result)")
        status(false, "Connexion interrompue — nouvelle tentative automatique (\(result))")
    }

    @discardableResult private func send(_ bytes: [UInt8]) -> Bool {
        guard let device else { return false }
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { failed(result, operation: "écriture USB"); return false }
        return true
    }

    func display(images: [(Int, Data)], brightness: Int, reinitialize: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard loop != nil, !stopped, !suspended, !displaySleeping else { return }
        var batch = pendingDisplay ?? PendingDeckDisplay()
        batch.merge(images: images, brightness: brightness, reinitialize: reinitialize)
        pendingDisplay = batch
    }

    private func drainDisplay() {
        lock.lock(); let batch = pendingDisplay; pendingDisplay = nil; lock.unlock()
        guard let batch else { return }
        if batch.reinitialize { initialized = false }
        if !initialized {
            guard send(DeckProtocol.command("DIS")), send(DeckProtocol.command("LIG", tail: [0,0,0,0])) else { return }
            // Clear every slot and commit the clear before uploading new images.
            for packet in DeckProtocol.clearScreenPackets { guard send(packet) else { return } }
            initialized = true
        }
        guard send(DeckProtocol.command("LIG", tail: [0,0,UInt8(batch.brightness)])) else { return }
        for (index, jpeg) in batch.images.sorted(by: { $0.key < $1.key }) {
            for packet in DeckProtocol.imagePackets(jpeg, index: index) { guard send(packet) else { return } }
        }
        guard send(DeckProtocol.command("STP")) else { return }
        retry.succeeded()
        commits += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCommitLog >= 30 {
            lastCommitLog = now
            logger.info("Affichages transmis : \(self.commits)")
        }
        status(true, "Soomfon connecté · 15 touches")
    }

    private func blankDisplay() {
        for packet in DeckProtocol.sleepPackets { guard send(packet) else { return } }
        initialized = false; displayBlanked = true
        retry.succeeded()
        logger.info("Commande de veille HAN transmise au boîtier")
    }

    func setDisplaySleeping(_ sleeping: Bool) {
        lock.lock(); displaySleeping = sleeping
        if sleeping { pendingDisplay = nil }
        lock.unlock()
    }

    func reconnect() {
        lock.lock(); reconnectRequested = true; lock.unlock()
    }
    func suspend() {
        lock.lock(); suspended = true; pendingDisplay = nil; lock.unlock()
    }
    func resume() {
        lock.lock(); suspended = false; reconnectRequested = true; lock.unlock()
    }
    func stop() {
        lock.lock(); stopped = true; let current = loop; lock.unlock()
        if let current { CFRunLoopWakeUp(current) }
    }
}
