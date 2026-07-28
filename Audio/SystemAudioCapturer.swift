import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Accelerate

protocol SystemAudioCapturer: AnyObject {
    func start(writer: AudioFileWriter) async throws
    func stop()
    var levelHandler: (@Sendable (Float) -> Void)? { get set }
    var videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)? { get set }
}

/// SCStream-based capture. Records system audio to a WAV file and forwards
/// 720p@15fps video frames to `videoFrameHandler` for the live preview.
final class ScreenCaptureAudioCapturer: NSObject, SystemAudioCapturer,
                                        SCStreamOutput, SCStreamDelegate {
    var levelHandler: (@Sendable (Float) -> Void)?
    var videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)?

    private var stream: SCStream?
    private var writer: AudioFileWriter?
    private let sampleQueue = DispatchQueue(label: "murmur.systemaudio.samples")
    private var isStopping = false

    func start(writer: AudioFileWriter) async throws {
        sampleQueue.sync { self.isStopping = false }
        self.writer = writer

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Real video for the live preview (720p @ 15 fps).
        config.width = 1280
        config.height = 720
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,  sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        sampleQueue.sync { self.isStopping = true }
        let capturedStream = stream
        stream = nil
        let capturedWriter = writer
        writer = nil
        capturedStream?.stopCapture { _ in capturedWriter?.finish() }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard !isStopping, sampleBuffer.isValid else { return }
        switch type {
        case .audio:
            guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
            writer?.append(pcm)
            if let handler = levelHandler {
                handler(min(Self.rms(pcm) * 5, 1.0))
            }
        case .screen:
            videoFrameHandler?(sampleBuffer)
        @unknown default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("SCStream stopped with error: \(error)")
    }

    // MARK: - Helpers

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fmtDesc = sampleBuffer.formatDescription,
              let asbd = fmtDesc.audioStreamBasicDescription else { return nil }
        var desc = asbd
        guard let format = AVAudioFormat(streamDescription: &desc) else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let n = vDSP_Length(buffer.frameLength)
        guard n > 0 else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(data[0], 1, &result, n)
        return result
    }

    enum CaptureError: Error { case noDisplay }
}
