import SwiftUI

struct SettingsView: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Local LLM (Ollama)") {
                TextField("Model", text: $controller.ollamaModel)
                Text("Run `ollama pull \(controller.ollamaModel)` in Terminal first. Good options: llama3.1:8b, qwen2.5:7b, mistral:7b.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Label("Audio is transcribed on-device with WhisperKit and never leaves your Mac.",
                      systemImage: "lock.shield")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 220)
    }
}
