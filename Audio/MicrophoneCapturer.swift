import Foundation
import AVFoundation

/// Captures the microphone via `AVAudioEngine` and streams buffers to a writer.
final class MicrophoneCapturer {
    private let engine = AVAudioEngine()
    private var writer: AudioFileWriter?
    private var isRunning = false

    /// Request microphone access. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            default:
                cont.resume(returning: false)
            }
        }
    }

    /// Start capturing into the given writer.
    func start(writer: AudioFileWriter) throws {
        guard !isRunning else { return }
        self.writer = writer

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)   // device-native format

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.writer?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer?.finish()
        writer = nil
        isRunning = false
    }
}
