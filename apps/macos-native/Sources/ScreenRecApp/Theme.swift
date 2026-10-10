import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Design tokens from the PRD (blue accent).
enum Theme {
    static let base = Color(hex: 0x111318)
    static let panel = Color(hex: 0x1C2028)
    static let bar = Color(hex: 0x20252E)
    static let hover = Color(hex: 0x2A3240)
    static let line = Color(hex: 0x333B49)
    static let blue = Color(hex: 0x2563EB)
    static let blueBright = Color(hex: 0x3B82F6)
    static let blueFocus = Color(hex: 0x60A5FA)
    static let blueTint = Color(hex: 0x3B82F6, opacity: 0.16)
    static let text = Color(hex: 0xF5F7FB)
    static let text2 = Color(hex: 0xA8B2C1)
    static let text3 = Color(hex: 0x788397)
    static let ok = Color(hex: 0x22C55E)
    static let bad = Color(hex: 0xEF4444)
    static let clip = Color(hex: 0xF59E0B)
    static let maskTint = Color(hex: 0x14B8A6)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 30)
            .foregroundStyle(.white)
            .background(configuration.isPressed ? Theme.blueBright : Theme.blue, in: RoundedRectangle(cornerRadius: 8))
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
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.blueBright : Color.clear, lineWidth: 1))
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
                .foregroundStyle(active ? Theme.blueFocus : (disabled ? Theme.text3.opacity(0.5) : Theme.text2))
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
            if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true) }
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
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true) }
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
                Text(format(value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text3)
                if let d = defaultValue {
                    Button("Reset") { value = d }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(value == d ? Theme.text3.opacity(0.5) : Theme.blueFocus).disabled(value == d)
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
