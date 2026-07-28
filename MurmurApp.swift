import SwiftUI
import SwiftData

@main
struct MurmurApp: App {
    let container: ModelContainer
    @State private var controller: RecordingController
    @State private var calendarMonitor: CalendarMonitor

    init() {
        do {
            container = try ModelContainer(for: Meeting.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        let ctrl = RecordingController(context: container.mainContext)
        _controller = State(initialValue: ctrl)
        _calendarMonitor = State(initialValue: CalendarMonitor())
    }

    var body: some Scene {
        Window("Murmur", id: "main") {
            ContentView()
                .environment(controller)
                .environment(calendarMonitor)
                .task {
                    calendarMonitor.controller = controller
                    await calendarMonitor.requestAccessIfNeeded()
                }
        }
        .modelContainer(container)

        MenuBarExtra {
            MenuBarView()
                .environment(controller)
        } label: {
            Image(systemName: controller.isRecording ? "record.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(controller)
                .environment(calendarMonitor)
        }
    }
}
