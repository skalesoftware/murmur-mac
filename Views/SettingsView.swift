import SwiftUI

struct SettingsView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(CalendarMonitor.self) private var calendar

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                CalendarSection()
            } header: {
                Label("Calendar", systemImage: "calendar")
            }

            Section {
                TextField("Model", text: $controller.ollamaModel)
                Text("Run `ollama pull \(controller.ollamaModel)` in Terminal first.\nOptions: llama3.1:8b, qwen2.5:7b, mistral:7b.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Local LLM (Ollama)", systemImage: "cpu")
            }

            Section {
                Label("Audio is transcribed on-device with WhisperKit and never leaves your Mac.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Privacy", systemImage: "hand.raised")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
    }
}

// Separate view so @Bindable works naturally on the CalendarMonitor environment value.
private struct CalendarSection: View {
    @Environment(CalendarMonitor.self) private var calendar

    var body: some View {
        @Bindable var calendar = calendar

        if !calendar.accessGranted {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar access required")
                        .font(.subheadline.weight(.medium))
                    Text("Murmur reads your calendars to detect when meetings start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant Access") {
                    Task { await calendar.requestAccessIfNeeded() }
                }
            }
            Button("Open Privacy Settings…") {
                calendar.openCalendarSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Toggle("Auto-start recording from calendar events", isOn: $calendar.isEnabled)

            if calendar.isEnabled {
                if let event = calendar.upcomingEvent {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title ?? "Meeting")
                                .font(.subheadline)
                            Text(event.startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No meetings starting in the next 5 minutes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text("Recording starts automatically when an event begins and stops when it ends. All-day events are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
