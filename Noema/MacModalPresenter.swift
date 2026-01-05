#if os(macOS)
import SwiftUI
import AppKit

@MainActor
final class MacModalPresenter: ObservableObject {
    @Published private(set) var presentation: MacModalPresentation?

    var isPresented: Bool { presentation != nil }

    func present<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        showCloseButton: Bool = true,
        dimensions: MacModalDimensions = .default,
        contentInsets: EdgeInsets = EdgeInsets(top: 24, leading: 28, bottom: 28, trailing: 28),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        let dismissAction = MacModalDismissAction { [weak self] in
            self?.dismiss()
        }

        let wrappedContent = AnyView(
            content()
                .environment(\.macModalDismiss, dismissAction)
        )
        withAnimation(.easeInOut(duration: 0.22)) {
            presentation = MacModalPresentation(
                title: title,
                subtitle: subtitle,
                showCloseButton: showCloseButton,
                dimensions: dimensions,
                contentInsets: contentInsets,
                content: wrappedContent,
                onDismiss: onDismiss
            )
        }
    }

    func update(title: String? = nil, subtitle: String? = nil) {
        guard var current = presentation else { return }
        if let title {
            current.title = title
        }
        if let subtitle {
            current.subtitle = subtitle
        }
        presentation = current
    }

    func dismiss(triggerCallback: Bool = true) {
        guard let current = presentation else { return }
        presentation = nil
        if triggerCallback {
            current.onDismiss?()
        }
    }
}

struct MacModalDimensions {
    var minWidth: CGFloat?
    var idealWidth: CGFloat?
    var maxWidth: CGFloat?
    var minHeight: CGFloat?
    var idealHeight: CGFloat?
    var maxHeight: CGFloat?

    static let `default` = MacModalDimensions(
        minWidth: 520,
        idealWidth: 560,
        maxWidth: 640,
        minHeight: 460,
        idealHeight: 520,
        maxHeight: 640
    )

    static let modelSettings = MacModalDimensions(
        minWidth: 620,
        idealWidth: 700,
        maxWidth: 820,
        minHeight: 560,
        idealHeight: 680,
        maxHeight: 860
    )
}

struct MacModalPresentation: Identifiable {
    let id = UUID()
    var title: String?
    var subtitle: String?
    let showCloseButton: Bool
    let dimensions: MacModalDimensions
    let contentInsets: EdgeInsets
    let content: AnyView
    let onDismiss: (() -> Void)?
}

struct MacModalDismissAction {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction() {
        handler()
    }
}

private struct MacModalDismissKey: EnvironmentKey {
    static let defaultValue = MacModalDismissAction { }
}

extension EnvironmentValues {
    @MainActor var macModalDismiss: MacModalDismissAction {
        get { self[MacModalDismissKey.self] }
        set { self[MacModalDismissKey.self] = newValue }
    }
}

struct MacModalHost: View {
    @EnvironmentObject private var presenter: MacModalPresenter

    var body: some View {
        Group {
            if let presentation = presenter.presentation {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { presenter.dismiss() }

                    modalCard(for: presentation)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                        .compositingGroup()
                        .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: presenter.presentation != nil)
    }

    @ViewBuilder
    private func modalCard(for presentation: MacModalPresentation) -> some View {
        let cornerRadius: CGFloat = 26

        VStack(spacing: 0) {
            if presentation.title != nil || presentation.showCloseButton {
                header(for: presentation)
            }

            presentation.content
                .padding(presentation.contentInsets)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.12), radius: 22, x: 0, y: 18)
        .frame(
            minWidth: presentation.dimensions.minWidth,
            idealWidth: presentation.dimensions.idealWidth,
            maxWidth: presentation.dimensions.maxWidth,
            minHeight: presentation.dimensions.minHeight,
            idealHeight: presentation.dimensions.idealHeight,
            maxHeight: presentation.dimensions.maxHeight,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func header(for presentation: MacModalPresentation) -> some View {
        let headerHorizontalPadding = max(
            24,
            max(presentation.contentInsets.leading, presentation.contentInsets.trailing)
        )
        let headerTopPadding = max(24, presentation.contentInsets.top)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = presentation.title {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if presentation.showCloseButton {
                    Button {
                        presenter.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            .padding(.bottom, presentation.contentInsets.top > 0 ? 12 : 0)
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.top, headerTopPadding)
    }
}
#endif
