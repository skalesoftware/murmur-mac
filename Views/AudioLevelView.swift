import SwiftUI

/// Horizontal bar-graph level meter.
struct AudioLevelView: View {
    let level: Float   // 0 to 1
    let color: Color
    let icon: String
    let label: String

    private let barCount = 22

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(level > 0.02 ? color : .secondary)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let threshold = Float(i) / Float(barCount)
                    // Bars past 85% turn orange to hint at clipping.
                    let barColor: Color = i < barCount * 85 / 100 ? color : .orange
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(level > threshold
                              ? barColor.opacity(0.85)
                              : Color.primary.opacity(0.07))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 12)
            .animation(.linear(duration: 0.06), value: level)
        }
    }
}
