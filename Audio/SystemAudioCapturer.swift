import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// Abstraction over "capture whatever the Mac is playing through its speakers."
/// The MVP implementation uses ScreenCaptureKit. A Core Audio process-tap
/// implementation (no screen-recording prompt, macOS 14.4+) can be dropped in
/// behind this same protocol — see Murmur-Design.md §7.
protocol SystemAudioCapturer: AnyObject {
    func start(writer: AudioFileWriter) async throws
    func stop()
}

/// System-audio capture via ScreenCaptureKit. Captures audio only (a minimal 2×2
/// video stream is configured but its frames are discarded) and excludes our own
/// process audio so we don't record Murmur's own UI sounds.
final class ScreenCaptureAudioCapturer: NSObject, SystemAudioCapturer, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AudioFileWriter?
    private let sampleQueue = DispatchQueue(label: "murmur.systemaudio.samples")
    /// Guards against late sample buffers re-opening the writer after stop().
    /// Only touched on `sampleQueue`.
    private var isStopping = false

    func start(writer: AudioFileWriter) async throws {
        sampleQueue.sync { self.isStopping = false }
        self.writer = writer

        // Pick the main display; audio is global regardless of which display we filter on.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Minimal video — required by SCStream but discarded. Small size + 1 fps = cheap.
        config.width = 128
        config.height = 128
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        // Stop accepting samples first (on the sample queue, in-order with callbacks),
        // then tear the stream down and flush the writer once no more buffers can arrive.
        sampleQueue.sync { self.isStopping = true }
        let capturedStream = stream
        stream = nil
        let capturedWriter = writer
        writer = nil
        capturedStream?.stopCapture { _ in
            capturedWriter?.finish()
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // This callback runs on `sampleQueue`; `isStopping` is safe to read here.
        guard !isStopping, type == .audio, sampleBuffer.isValid,
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        writer?.append(pcm)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("SCStream stopped with error: \(error)")
    }

    // MARK: - CMSampleBuffer -> AVAudioPCMBuffer

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fmtDesc = sampleBuffer.formatDescription,
              let asbd = fmtDesc.audioStreamBasicDescription else { return nil }

        var streamDesc = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }

        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames

        // Copy the sample data into the PCM buffer's audio buffer list.
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: pcm.mutableAudioBufferList
        )
        return status == noErr ? pcm : nil
    }

    enum CaptureError: Error { case noDisplay }
}
