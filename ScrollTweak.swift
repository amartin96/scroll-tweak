import SwiftUI

// Must extend NSObject so selectors can be used
class EventListener: NSObject {
    let lines: UnsafeMutablePointer<Int64>
    let thread: Thread
    var runloop: CFRunLoop!

    init?(lines: Int64) {
        self.lines = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.lines.initialize(to: lines)

        // Create the scroll wheel event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, _, event, userInfo in
                // If this is a continuous i.e. trackpad scroll, do nothing
                if 0 == event.getIntegerValueField(CGEventField.scrollWheelEventIsContinuous) {
                    let delta: Int64 = event.getIntegerValueField(CGEventField.scrollWheelEventPointDeltaAxis1)
                    event.setIntegerValueField(CGEventField.scrollWheelEventDeltaAxis1, value: delta.signum() * userInfo!.load(as: Int64.self))
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: self.lines
        ) else {
            print("Failed to create scroll wheel event tap")
            return nil
        }

        // Create a run loop source from the event tap
        guard let eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else {
            print("Failed to create scroll wheel run loop source")
            return nil
        }

        thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .commonModes)
            CFRunLoopRun()
        }
        thread.start()
    }

    deinit {
        print("deinit")
        self.lines.deallocate()
        self.perform(#selector(stop), on: self.thread, with: nil, waitUntilDone: true)
    }

    @objc private func stop() {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventListener: EventListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventListener = EventListener(lines: 3)
    }

    func toggle(lines: Int64) {
        print("toggle")
        if eventListener != nil {
            print("toggle off")
            eventListener = nil
        } else {
            print("toggle on")
            eventListener = EventListener(lines: lines)
        }
    }
}

struct MyView: View {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var isOn = true
    @State private var lines: Double = 3

    var body: some View {
        List {
            Toggle("ScrollTweak", isOn: $isOn).toggleStyle(.switch)
            HStack {
                Text("# Lines")
                Slider(value: $lines, in: 1...10, step: 1).disabled(isOn)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }.onChange(of: isOn) {
            print("isOn=\(isOn)")
            appDelegate.toggle(lines: Int64(lines))
        }.onChange(of: lines) {
            print("lines=\(lines)")
        }.listStyle(.sidebar)
    }
}

@main
struct ScrollTweak: App {
    var body: some Scene {
        return MenuBarExtra("", systemImage: "computermouse.fill") {
            MyView()
        }.menuBarExtraStyle(.window)
    }
}
