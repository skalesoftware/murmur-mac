import Foundation
import AVFoundation
import Accelerate

final class MicrophoneCapturer {
    /// Called on an arbitrary thread with a normalized RMS level [0, 1].
    var levelHandler: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private var writer: AudioFileWriter?
    private var isRunning = false

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:  cont.resume(returning: true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            default: cont.resume(returning: false)
            }
        }
    }

    func start(writer: AudioFileWriter) throws {
        guard !isRunning else { return }
        self.writer = writer

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.writer?.append(buffer)
            if let handler = self?.levelHandler {
                // Clamp and scale: typical mic RMS sits in 0.01–0.15 range.
                handler(min(Self.rms(buffer) * 8, 1.0))
            }
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

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let n = vDSP_Length(buffer.frameLength)
        guard n > 0 else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(data[0], 1, &result, n)
        return result
    }
}
