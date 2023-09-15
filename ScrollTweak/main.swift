// Each thread comes with its own runloop
// Start a new thread for the scroll event tap runloop
// Give it a message port too so we can tell it to shut down
// Use the main thread for the application

// TODO
// - Can only stop the thread once. Subsequent attempts keep starting more threads without stopping the old ones.
// - Restarting the thread doesn't capture scroll events properly?

import AppKit
import Foundation

enum EventManager {
    case Valid(_ thread: EventThread)
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
            print("Failed to create event tap")
            self = .Invalid
            return
        }
        
        self = .Valid(EventThread(eventTap))
    }
}

struct EventThread {
    var thread: Thread
    private let eventTap: CFMachPort
    private let eventSource: CFRunLoopSource
    private let messagePort: CFMessagePort
    private let messageSource: CFRunLoopSource
    
    private static func startNewThread(_ eventSource: CFRunLoopSource, _ messageSource: CFRunLoopSource) -> Thread {
        print("Creating thread")
        let thread = Thread {
            print("Run loop thread started: \(Thread.current.name)")
            CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), messageSource, .commonModes)
            CFRunLoopRun()
            print("Run loop thread exiting")
        }
        thread.name = UUID().uuidString
        print("Starting thread")
        thread.start()
        print("thread.start() called, isExecuting: \(thread.isExecuting)")
        return thread
    }
    
    init(_ eventTap: CFMachPort) {
        // Keep the handle to the event tap so we can release it later
        self.eventTap = eventTap
        
        // Create a runloop source from the tap
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        // Create a message port so we can stop the thread
        messagePort = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            "" as CFString,
            { _, _, _, _ in
                print("Stopping run loop")
                CFRunLoopStop(CFRunLoopGetCurrent())
                return nil
            },
            nil,
            nil
        )
        messageSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, messagePort, 0)
        thread = EventThread.startNewThread(eventSource, messageSource)
        print("EventThread.startNewThread called, isExecuting: \(thread.isExecuting)")
    }

    mutating func toggle() {
        if thread.isExecuting {
            print("Toggling off")
            if CFMessagePortSendRequest(messagePort, 0, nil, 30, 0, nil, nil) != kCFMessagePortSuccess {
                // TODO failed to send message
                print("Failed to send message")
            }
        } else {
            print("Toggling on")
            let oldThread = thread
            thread = EventThread.startNewThread(eventSource, messageSource)
            print("oldThread === thread: \(oldThread === thread)")
        }
    }
}

class App: NSObject, NSApplicationDelegate {
    var loop: EventManager!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loop = EventManager()

        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.title = "+"
        let menu = NSMenu()
        menu.addItem(withTitle: "Stop", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Status", action: #selector(status), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(terminate), keyEquivalent: "")
        statusItem.menu = menu
    }
    
    @objc private func toggle() {
        if case .Valid(var thread) = loop {
            thread.toggle()
        } else {
            print("EventManager is invalid")
        }
    }
    
    @objc private func status() {
        if case .Valid(let thread) = loop {
            print("thread \(thread.thread.name) isExecuting: \(thread.thread.isExecuting)")
        } else {
            print("EventManager is invalid")
        }
    }

    @objc private func terminate() {
        NSApp.terminate(self)
    }
}

let delegate = App()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
