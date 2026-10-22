import SwiftUI

/// Rounded card container, Superwhisper-style: content rows separated by dividers.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One labeled row inside a SettingsCard: title (+ optional subtitle) left, control right.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct CardDivider: View {
    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 16)
    }
}

/// Section heading above a card.
struct PaneSectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .padding(.top, 6)
    }
}

/// Pane scaffold: big title, optional trailing control, scrollable content.
struct PaneScaffold<Content: View, TrailingItem: View>: View {
    let title: String
    @ViewBuilder var trailing: TrailingItem
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                trailing
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension PaneScaffold where TrailingItem == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// Superwhisper-style speed/accuracy indicator: five rounded dashes.
struct RatingDashes: View {
    let value: Int // 0…5
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < value ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 11, height: 3)
            }
        }
    }
}

/// Colored rounded-square icon chip used in the sidebar and lists.
struct IconChip: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}
