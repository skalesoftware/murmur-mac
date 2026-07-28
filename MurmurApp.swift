import SwiftUI
import SwiftData

@main
struct MurmurApp: App {
    /// Shared SwiftData container for all `Meeting` records.
    let container: ModelContainer

    /// The single coordinator that owns recording state for the whole app.
    @State private var controller: RecordingController

    init() {
        do {
            container = try ModelContainer(for: Meeting.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        _controller = State(initialValue: RecordingController(context: container.mainContext))
    }

    var body: some Scene {
        // Single main window (not a WindowGroup) so "Open Murmur" focuses the
        // existing window instead of spawning duplicates.
        Window("Murmur", id: "main") {
            ContentView()
                .environment(controller)
        }
        .modelContainer(container)

        // Always-present menu-bar control, Granola-style.
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
        }
    }
}
