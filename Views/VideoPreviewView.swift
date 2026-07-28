import SwiftUI
import AVFoundation
import CoreMedia

/// Wraps an AVSampleBufferDisplayLayer to show live SCStream video frames.
struct VideoPreviewView: NSViewRepresentable {
    let frame: CMSampleBuffer?

    func makeNSView(context: Context) -> VideoLayerView { VideoLayerView() }

    func updateNSView(_ view: VideoLayerView, context: Context) {
        if let f = frame { view.enqueue(f) }
    }
}

final class VideoLayerView: NSView {
    private let display = AVSampleBufferDisplayLayer()

    override init(frame r: NSRect) { super.init(frame: r); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        display.videoGravity = .resizeAspect
        display.backgroundColor = CGColor(gray: 0.06, alpha: 1)
        layer?.addSublayer(display)

        // Timebase anchored to the host clock so incoming frames show immediately.
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb)
        if let tb {
            CMTimebaseSetTime(tb, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(tb, rate: 1.0)
            display.controlTimebase = tb
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.frame = bounds
        CATransaction.commit()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard display.isReadyForMoreMediaData else { return }
        display.enqueue(sampleBuffer)
    }
}
