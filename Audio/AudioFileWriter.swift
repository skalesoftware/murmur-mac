import Foundation
import AVFoundation

/// Whisper's expected input format: 16 kHz, mono, Float32.
enum WhisperAudio {
    static let sampleRate: Double = 16_000
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
}

/// Receives audio buffers in *any* input format, converts them to 16 kHz mono
/// Float32, and appends them to a `.wav` file on disk. Safe for long meetings —
/// nothing is held in memory beyond one buffer at a time.
///
/// Thread-safety: `append(_:)` may be called from an audio callback thread. All
/// mutation is funneled through a serial queue so a single writer instance can
/// be fed from a single source safely.
final class AudioFileWriter {
    private let url: URL
    private let queue: DispatchQueue
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init(url: URL, label: String) {
        self.url = url
        self.queue = DispatchQueue(label: "murmur.audiowriter.\(label)")
    }

    /// Append one buffer. Lazily creates the file/converter on the first buffer,
    /// using that buffer's format as the conversion source.
    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ensureReady(for: buffer.format)
                guard let converted = self.convert(buffer) else { return }
                try self.file?.write(from: converted)
            } catch {
                NSLog("AudioFileWriter append error: \(error)")
            }
        }
    }

    /// Flush and close. Blocks until pending writes finish.
    func finish() {
        queue.sync {
            self.file = nil          // AVAudioFile flushes on deinit
            self.converter = nil
        }
    }

    // MARK: - Private

    private func ensureReady(for format: AVAudioFormat) throws {
        if file == nil {
            // WAV settings: 16 kHz mono, 16-bit PCM (widely compatible with WhisperKit).
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: WhisperAudio.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            file = try AVAudioFile(forWriting: url, settings: settings)
        }
        if converter == nil || inputFormat != format {
            inputFormat = format
            converter = AVAudioConverter(from: format, to: WhisperAudio.format)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let inputFormat, buffer.frameLength > 0 else { return nil }

        // Output capacity scaled by the sample-rate ratio (+ headroom).
        let ratio = WhisperAudio.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(
            pcmFormat: WhisperAudio.format,
            frameCapacity: capacity
        ) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inStatus in
            if consumed {
                inStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inStatus.pointee = .haveData
            return buffer
        }

        if let error {
            NSLog("AudioConverter error: \(error)")
            return nil
        }
        return status == .error ? nil : out
    }
}
