import CameraKit
import SwiftUI

/// Settings-style slider row: label on the left, slider with end icons on the right,
/// like Brightness in System Settings › Displays. The exact value shows as a tooltip.
struct ControlSlider<MinLabel: View, MaxLabel: View>: View {
    let title: String
    @Binding var value: Int
    let range: ControlRange
    @ViewBuilder var minimumLabel: MinLabel
    @ViewBuilder var maximumLabel: MaxLabel

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                minimumLabel.foregroundStyle(.secondary).frame(minWidth: 18)
                Slider(value: doubleValue, in: Double(range.min)...Double(max(range.max, range.min + 1)))
                    .labelsHidden()
                maximumLabel.foregroundStyle(.secondary).frame(minWidth: 18)
            }
            .frame(maxWidth: 240)
        }
        .help("\(title): \(value)")
    }

    /// Snaps to the control's resolution without drawing tick marks.
    private var doubleValue: Binding<Double> {
        Binding(get: { Double(value) },
                set: { newValue in
                    let step = Double(max(range.step, 1))
                    let snapped = Int((newValue / step).rounded() * step)
                    if snapped != value { value = range.clamp(snapped) }
                })
    }
}

extension ControlSlider where MinLabel == SymbolLabel, MaxLabel == SymbolLabel {
    init(_ title: String, value: Binding<Int>, range: ControlRange, minimumSymbol: String, maximumSymbol: String) {
        self.init(title: title, value: value, range: range,
                  minimumLabel: { SymbolLabel(name: minimumSymbol, scale: .small) },
                  maximumLabel: { SymbolLabel(name: maximumSymbol, scale: .medium) })
    }
}

struct SymbolLabel: View {
    let name: String
    let scale: Image.Scale

    var body: some View {
        Image(systemName: name).imageScale(scale)
    }
}
