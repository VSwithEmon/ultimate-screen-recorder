import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Design tokens from the PRD (blue accent), tuned to WCAG 2.1 AA: text >= 4.5:1, control boundaries >= 3:1.
/// Raw values are exposed so tests can verify contrast.
enum Palette {
    static let base: UInt32 = 0x111318
    static let panel: UInt32 = 0x1C2028
    static let bar: UInt32 = 0x20252E
    static let hover: UInt32 = 0x2A3240
    static let line: UInt32 = 0x333B49          // decorative dividers only
    static let control: UInt32 = 0x7A8599       // borders/tracks of interactive controls (>= 3:1)
    static let blue: UInt32 = 0x2563EB          // fills carrying white text (5.2:1)
    static let bluePressed: UInt32 = 0x1D4ED8
    static let blueBright: UInt32 = 0x3B82F6    // borders/indicators only
    static let blueFocus: UInt32 = 0x60A5FA     // accent text
    static let text: UInt32 = 0xF5F7FB
    static let text2: UInt32 = 0xD8DEE9
    static let text3: UInt32 = 0xB6BFCE
    static let ok: UInt32 = 0x4ADE80
    static let bad: UInt32 = 0xF87171
    static let clip: UInt32 = 0xF59E0B
    static let clipText: UInt32 = 0x2B1700
    static let maskFill: UInt32 = 0x0F766E      // white text 5.5:1
    static let highlightFill: UInt32 = 0x4F46E5 // white text 6.3:1
}

enum Theme {
    static let base = Color(hex: Palette.base)
    static let panel = Color(hex: Palette.panel)
    static let bar = Color(hex: Palette.bar)
    static let hover = Color(hex: Palette.hover)
    static let line = Color(hex: Palette.line)
    static let control = Color(hex: Palette.control)
    static let blue = Color(hex: Palette.blue)
    static let bluePressed = Color(hex: Palette.bluePressed)
    static let blueBright = Color(hex: Palette.blueBright)
    static let blueFocus = Color(hex: Palette.blueFocus)
    static let blueTint = Color(hex: Palette.blueBright, opacity: 0.16)
    static let text = Color(hex: Palette.text)
    static let text2 = Color(hex: Palette.text2)
    static let text3 = Color(hex: Palette.text3)
    static let ok = Color(hex: Palette.ok)
    static let bad = Color(hex: Palette.bad)
    static let clip = Color(hex: Palette.clip)
    static let maskTint = Color(hex: Palette.maskFill)
    static let highlightTint = Color(hex: Palette.highlightFill)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 30)
            .foregroundStyle(.white)
            .background(configuration.isPressed ? Theme.bluePressed : Theme.blue, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct QuietButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9).frame(minHeight: 28)
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .background(selected ? Theme.blueTint : (configuration.isPressed ? Theme.hover : Color.clear), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.blueFocus : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct IconButton: View {
    let system: String
    var help: String
    var active = false
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(active ? Theme.blueFocus : (disabled ? Theme.text3 : Theme.text))
                .background(active ? Theme.blueTint : (hover && !disabled ? Theme.hover : Color.clear), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).disabled(disabled).help(help).onHover { hover = $0 }
        .accessibilityLabel(help)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true) }
            content
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var disabled = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.blue).controlSize(.small)
        }
        .padding(.vertical, 8).opacity(disabled ? 0.45 : 1).disabled(disabled)
        .accessibilityElement(children: .combine)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var defaultValue: Double?
    var format: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(format(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                if let d = defaultValue {
                    Button("Reset") { value = d }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(value == d ? Theme.text3.opacity(0.75) : Theme.blueFocus).disabled(value == d)
                }
            }
            Slider(value: $value, in: range).tint(Theme.blue).controlSize(.small)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Chip group acting like the segmented controls in the reference.
struct ChipPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].1) { selection = options[i].0 }
                    .buttonStyle(QuietButtonStyle(selected: selection == options[i].0))
            }
        }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) { content }.padding(16) }
            .background(Theme.panel)
    }
}


extension View {
    /// Recorder panels float over arbitrary apps and must stay dark in light mode too.
    func recorderPanelStyle() -> some View { self.environment(\.colorScheme, .dark).preferredColorScheme(.dark) }
}

extension NSWindow {
    func forceDarkAppearance() { appearance = NSAppearance(named: .darkAqua) }
}
