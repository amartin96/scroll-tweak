import AppKit

// Must extend NSObject so selectors can be used
class EventListener: NSObject {
    let thread: Thread
    let eventTap: CFMachPort
    let eventSource: CFRunLoopSource
    var runloop: CFRunLoop!

    // Need this dummy parameter because NSObject.init() can't be overridden by init?()
    init?(_: Void) {
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

        thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .commonModes)
            CFRunLoopRun()
        }
        thread.start()
    }

    deinit {
        self.perform(#selector(stop), on: self.thread, with: nil, waitUntilDone: true)
    }

    @objc private func stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

class App: NSObject, NSApplicationDelegate {
    var eventListener: EventListener?

    // NSStatusBar.system doesn't take ownership of its items, so we must retain ours
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventListener = EventListener(())
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button!.title = "ScrollTweak"
        statusItem.menu = NSMenu()
        statusItem.menu!.addItem(withTitle: "Stop", action: #selector(toggle), keyEquivalent: "")
        statusItem.menu!.addItem(withTitle: "Quit", action: #selector(terminate), keyEquivalent: "")
    }

    @objc private func toggle() {
        if eventListener != nil {
            eventListener = nil
            statusItem.menu!.item(withTitle: "Stop")?.title = "Start"
        } else {
            eventListener = EventListener(())
            statusItem.menu!.item(withTitle: "Start")?.title = "Stop"
        }
    }

    @objc private func terminate() {
        NSApp.terminate(self)
    }
}

let delegate = App()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
