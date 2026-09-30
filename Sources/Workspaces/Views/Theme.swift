import SwiftUI
import WorkspacesCore

/// Black with small steps of grey. Full white only marks what waits for you.
enum Theme {
    static let background = Color.black
    static let sidebar = Color(white: 0.04)
    static let surface = Color(white: 0.067)
    static let control = Color(white: 0.086)
    static let selected = Color(white: 0.18)
    static let rowSelected = Color.white.opacity(0.09)
    static let rowHover = Color.white.opacity(0.05)
    static let divider = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.1)

    static let primary = Color(white: 0.96)
    static let support = Color(white: 0.83)
    static let secondary = Color(white: 0.63)
    static let tertiary = Color(white: 0.54)
    static let faint = Color(white: 0.36)

    static let mono = Font.system(size: 12, design: .monospaced)
}

struct StatusGlyph: View {
    let status: SessionStatus
    var attention = false
    var size: CGFloat = 12

    var body: some View {
        Group {
            if status == .waiting || attention {
                ZStack {
                    Circle().stroke(Theme.primary.opacity(0.35), lineWidth: 1)
                    Circle().fill(Theme.primary).padding(size * 0.25)
                }
            } else {
                switch status {
                case .working: WorkingArc()
                case .done:
                    CheckShape().stroke(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                default:
                    Circle().stroke(Theme.faint, lineWidth: 1.5).padding(size * 0.17)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(attention && status != .waiting ? "Pede sua atenção" : status.label)
    }
}

private struct WorkingArc: View {
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.primary.opacity(0.15), lineWidth: 1.5)
            Circle().trim(from: 0, to: 0.25)
                .stroke(Theme.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
        }
        .padding(1)
        .onAppear { spinning = true }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.39, y: rect.minY + rect.height * 0.71))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.3))
        return p
    }
}

/// Row with the hover and selected backgrounds of the sidebar and the menu bar.
struct RowButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, selected: selected)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Theme.rowSelected : (hovering || configuration.isPressed ? Theme.rowHover : .clear))
                )
                .onHover { hovering = $0 }
        }
    }
}

/// Two-option switch in the toolbar ("Uma" / "Grade").
struct SegmentedSwitch<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { title, value in
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selection == value ? .medium : .regular))
                        .foregroundStyle(selection == value ? Theme.primary : Theme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selection == value ? Theme.selected : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.control))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
    }
}
