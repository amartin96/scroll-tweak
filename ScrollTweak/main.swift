// Each thread comes with its own runloop
// Start a new thread for the scroll event tap runloop
// Use the main thread for the application

import AppKit
import Foundation

class App: NSObject, NSApplicationDelegate {
    var thread: Thread!
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let thread = Thread.init {
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                callback: { _, _, event, _ in
                    // If this is a continuous i.e. trackpad scroll, do nothing
                    if (0 == event.getIntegerValueField(CGEventField.scrollWheelEventIsContinuous)) {
                        let delta: Int64 = event.getIntegerValueField(CGEventField.scrollWheelEventPointDeltaAxis1)
                        event.setIntegerValueField(CGEventField.scrollWheelEventDeltaAxis1, value: delta.signum() * 3)
                    }
                    return Unmanaged.passRetained(event)
                },
                userInfo: nil
            ) else {
                return
            }

            let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

            CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, CFRunLoopMode.commonModes)

            CGEvent.tapEnable(tap: eventTap, enable: true)

            CFRunLoopRun()
        }
        thread.start()

        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.title = "+"
        menu = NSMenu.init()
        menu.addItem(withTitle: "Quit", action: #selector(terminate), keyEquivalent: "")
        statusItem.menu = menu
    }

    /// Marked @objc so it can be used as a selector
    @objc private func terminate() {
        NSApp.terminate(self)
    }
}

let delegate = App()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
