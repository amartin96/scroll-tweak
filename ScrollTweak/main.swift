import AppKit

class EventListener {
    let thread: Thread
    let eventTap: CFMachPort
    let eventSource: CFRunLoopSource
    let messagePort: CFMessagePort
    let messageSource: CFRunLoopSource
    var runloop: CFRunLoop!

    init?() {
        // Create the scroll wheel event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, _, event, _ in
                // If this is a continuous i.e. trackpad scroll, do nothing
                if 0 == event.getIntegerValueField(CGEventField.scrollWheelEventIsContinuous) {
                    let delta: Int64 = event.getIntegerValueField(CGEventField.scrollWheelEventPointDeltaAxis1)
                    event.setIntegerValueField(CGEventField.scrollWheelEventDeltaAxis1, value: delta.signum() * 3)
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            print("Failed to create scroll wheel event tap")
            return nil
        }
        self.eventTap = eventTap

        // Create a run loop source from the event tap
        guard let eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else {
            print("Failed to create scroll wheel run loop source")
            return nil
        }
        self.eventSource = eventSource

        // Create a message port so we can send a stop command to the thread
        guard let messagePort = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            "" as CFString,
            { _, _, _, _ in
                print("Stopping run loop")
                CFRunLoopStop(CFRunLoopGetCurrent())
                return nil
            },
            nil,
            nil
        ) else {
            print("Failed to create message port")
            return nil
        }
        self.messagePort = messagePort

        guard let messageSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, messagePort, 0)
        else {
            print("Failed to create message run loop source")
            return nil
        }
        self.messageSource = messageSource

        thread = Thread {
            print("Run loop thread started: \(Thread.current.name)")
            CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), messageSource, .commonModes)
            CFRunLoopRun()
            print("Run loop stopped, terminating thread")
        }
        thread.name = UUID().uuidString
        thread.start()
        print("thread.start() called, isExecuting: \(thread.isExecuting)")
    }

    deinit {
        print("deinit")
        if CFMessagePortSendRequest(messagePort, 0, nil, 30, 0, nil, nil) != kCFMessagePortSuccess {
            // TODO failed to send message
            print("Failed to send message")
        }
    }
}

class App: NSObject, NSApplicationDelegate {
    var eventListener: EventListener?
    var statusItem: NSStatusItem!

    override init() {
        print("init")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApp.setActivationPolicy(.regular)
        eventListener = EventListener()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.title = "+"
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle", action: #selector(toggle), keyEquivalent: "")
        // menu.addItem(withTitle: "Status", action: #selector(status), keyEquivalent: "")
        // menu.addItem(withTitle: "Quit", action: #selector(terminate), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc private func toggle() {
        if eventListener != nil {
            print("Stopping")
            eventListener = nil
        } else {
            print("Starting")
            eventListener = EventListener()
        }
    }
}

let delegate = App()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
