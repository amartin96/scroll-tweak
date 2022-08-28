// Each thread comes with its own runloop
// Start a new thread for the scroll event tap runloop
// Give it a message port too so we can tell it to shut down
// Use the main thread for the application

// TODO
// - Can only stop the thread once. Subsequent attempts keep starting more threads without stopping the old ones.
// - Restarting the thread doesn't capture scroll events properly?

import AppKit
import Foundation

enum EventLoop {
    case Valid(thread: EventThread)
    case Invalid
    
    init() {
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
            self = .Invalid
            return
        }
        
        self = .Valid(thread: EventThread(eventTap))
    }
}

struct EventThread {
    private var thread: Thread
    private let eventSource: CFRunLoopSource
    private let messagePort: CFMessagePort
    private let messageSource: CFRunLoopSource
    
    private static func startNewThread(_ eventSource: CFRunLoopSource, _ messageSource: CFRunLoopSource) -> Thread {
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), messageSource, .commonModes)
            CFRunLoopRun()
        }
        thread.start()
        return thread
    }
    
    init(_ eventTap: CFMachPort) {
        // Create a runloop source from the tap
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        // Create a message port so we can stop the thread
        messagePort = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            "" as CFString,
            { _, _, _, _ in
                print("Exiting thread")
                Thread.exit()
            
                print("This shouldn't happen")
                // This makes static analysis happy
                return nil
            },
            nil,
            nil
        )
        messageSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, messagePort, 0)
        thread = EventThread.startNewThread(eventSource, messageSource)
    }

    mutating func toggle() {
        print("Thread is currently executing: \(thread.isExecuting)")
        if thread.isExecuting {
            print("Stopping the event loop")
            if CFMessagePortSendRequest(messagePort, 0, nil, 30, 0, nil, nil) != kCFMessagePortSuccess {
                // TODO failed to send message
                print("Failed to send message")
            }
        } else {
            print("Starting the event loop")
            thread = EventThread.startNewThread(eventSource, messageSource)
        }
    }
}

class App: NSObject, NSApplicationDelegate {
    var loop: EventLoop!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loop = EventLoop()

        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.title = "+"
        let menu = NSMenu()
        menu.addItem(withTitle: "Stop", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(terminate), keyEquivalent: "")
        statusItem.menu = menu
    }
    
    @objc private func toggle() {
        if case .Valid(var thread) = loop {
            thread.toggle()
        }
    }

    @objc private func terminate() {
        NSApp.terminate(self)
    }
}

let delegate = App()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
