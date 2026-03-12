import SwiftUI

struct AppShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            MuniTheme.windowBackground.ignoresSafeArea()

            content
                .padding(MuniTheme.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ContentCard<Content: View>: View {
    var padding: CGFloat = MuniTheme.Spacing.md
    var cornerRadius: CGFloat = MuniTheme.Radius.md
    var fill: Color = MuniTheme.surfacePrimary
    var stroke: Color = MuniTheme.borderLight
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .muniSurface(cornerRadius: cornerRadius, fill: fill, stroke: stroke)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MuniTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MuniTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(MuniSecondaryButtonStyle())
        .disabled(isDisabled)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(MuniPrimaryButtonStyle())
        .disabled(isDisabled)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(MuniSecondaryButtonStyle())
        .disabled(isDisabled)
    }
}

struct StatusBadge: View {
    var title: String? = nil
    let value: String
    var tone: Color = MuniTheme.textPrimary

    var body: some View {
        HStack(spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(MuniTheme.textSecondary)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(MuniTheme.surfaceTertiary)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(MuniTheme.borderLight, lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: MuniTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(MuniTheme.textSecondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(MuniTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(MuniTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PreviewPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ContentCard(padding: MuniTheme.Spacing.sm, cornerRadius: MuniTheme.Radius.lg, fill: MuniTheme.surfaceSecondary) {
            content
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MuniTheme.splitDivider)
                .frame(width: 1)
                .padding(.vertical, MuniTheme.Spacing.md)
        }
    }
}

struct SidebarPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ContentCard(padding: MuniTheme.Spacing.sm, cornerRadius: MuniTheme.Radius.lg, fill: MuniTheme.surfaceSecondary) {
            content
        }
    }
}

struct InspectorPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ContentCard(padding: MuniTheme.Spacing.md, cornerRadius: MuniTheme.Radius.md, fill: MuniTheme.surfacePrimary) {
            content
        }
    }
}

struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MuniTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(MuniTheme.textSecondary)
                .frame(width: 120, alignment: .trailing)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
    }
}

struct SegmentedChoiceRow<Option: Hashable & Identifiable>: View {
    let title: String
    @Binding var selection: Option
    var options: [Option]
    var label: (Option) -> String

    var body: some View {
        HStack(alignment: .center, spacing: MuniTheme.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(MuniTheme.textSecondary)
                .frame(width: 120, alignment: .trailing)
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
