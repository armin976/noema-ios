#if !os(macOS)
import SwiftUI

struct EndpointTypeSelectionBoxes: View {
    @Binding var selection: RemoteBackend.EndpointType
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth, maximum: 220), spacing: 12, alignment: .leading)]
    }

    private var minimumColumnWidth: CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return 200
        case .compact:
            return 150
        default:
            return 170
        }
    }

    private var cardHeight: CGFloat {
        switch horizontalSizeClass {
        case .regular:
            return 160
        case .compact:
            return 148
        default:
            return 154
        }
    }

    private func cardBackground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.18)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05)
    }

    private func cardBorder(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.35)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(RemoteBackend.EndpointType.remoteEndpointOptions) { type in
                let isSelected = selection == type
                Button {
                    selection = type
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(isSelected ? 0.28 : 0.14))
                                    .frame(width: 36, height: 36)
                                Image(systemName: type.symbolName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.accentColor.opacity(0.75))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                Text(type.description)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(type.isRelay ? "Uses Noema Relay configuration" : "Chat: \(type.defaultChatPath)\nModels: \(type.defaultModelsPath)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(cardBackground(isSelected: isSelected))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorder(isSelected: isSelected), lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
                .accessibilityLabel(type.displayName)
                .accessibilityHint(type.description)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}
#endif
