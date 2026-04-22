import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IndexingNotificationView: View {
    @ObservedObject var datasetManager: DatasetManager

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    @State private var presentedBanner: PresentedBanner?
    @State private var showBanner = false
    @State private var isCollapsed = false
    @State private var showCancelConfirm = false
    @State private var showBatteryConfirm = false
    @State private var dismissTask: Task<Void, Never>?

    private let pillWidth: CGFloat = {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 460 : 0
        #else
        return 420
        #endif
    }()

    private let outerHorizontalPadding: CGFloat = {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 0 : 16
        #else
        return 0
        #endif
    }()

    private let collapsedPillWidth: CGFloat = {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? 260 : 208
        #else
        return 244
        #endif
    }()

    private var activeBanner: PresentedBanner? {
        guard
            let id = datasetManager.indexingDatasetID,
            let dataset = datasetManager.datasets.first(where: { $0.datasetID == id }),
            let status = datasetManager.processingStatus[id]
        else {
            return nil
        }
        return PresentedBanner(dataset: dataset, status: status)
    }

    private var bannerSignature: BannerSignature? {
        guard let banner = activeBanner else { return nil }
        return BannerSignature(
            datasetID: banner.dataset.datasetID,
            stage: banner.status.stage,
            progressStep: Int((banner.status.progress * 1000).rounded()),
            message: banner.status.message ?? ""
        )
    }

    var body: some View {
        Group {
            if let banner = presentedBanner {
                pill(for: banner)
                    .scaleEffect(showBanner ? 1.0 : 0.94)
                    .opacity(showBanner ? 1.0 : 0.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showBanner)
                    .transition(.opacity)
            }
        }
        .onAppear {
            syncPresentedBanner()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
        .onChangeCompat(of: bannerSignature) { _, _ in
            syncPresentedBanner()
        }
    }

    @ViewBuilder
    private func pill(for banner: PresentedBanner) -> some View {
        let presentation = DatasetIndexingPresentation.make(for: banner.status, locale: locale)

        Group {
            if isCollapsed {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    collapsedPill(for: banner, presentation: presentation)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)),
                                removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))
                            )
                        )
                }
            } else {
                expandedPill(for: banner, presentation: presentation)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing))
                        )
                    )
            }
        }
        .frame(maxWidth: pillWidth == 0 ? .infinity : pillWidth, alignment: isCollapsed ? .trailing : .center)
        .padding(.horizontal, outerHorizontalPadding)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isCollapsed)
        .contextMenu {
            Button(role: .destructive) {
                dismissCurrentBanner()
            } label: {
                Label(LocalizedStringKey("Dismiss"), systemImage: "xmark.circle")
            }
        }
    }

    private func expandedPill(for banner: PresentedBanner, presentation: DatasetIndexingPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                collapseBanner()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    headerRow(
                        datasetName: banner.dataset.name,
                        presentation: presentation,
                        toggleSystemImage: "chevron.right"
                    )

                    Group {
                        if presentation.showsProgressBar {
                            NotificationProgressBar(value: banner.status.progress, height: 7)
                        } else {
                            Capsule()
                                .fill(successTrackColor(for: presentation))
                                .frame(height: 7)
                        }
                    }

                    statusRow(presentation: presentation)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            actionRow(for: banner, presentation: presentation)
                .frame(height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: pillWidth == 0 ? .infinity : pillWidth)
        .glassPill(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.8)
        )
    }

    private func collapsedPill(for banner: PresentedBanner, presentation: DatasetIndexingPresentation) -> some View {
        Button {
            expandBanner()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor(for: presentation))
                    .frame(width: 16, height: 16)

                Text(banner.dataset.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .compactStatusText(minimumScaleFactor: 0.74)

                Spacer(minLength: 6)

                Text(collapsedProgressText(for: banner, presentation: presentation))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(secondaryTextColor)
                    .compactStatusText(minimumScaleFactor: 0.76)

                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: collapsedPillWidth)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassPill(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.8)
        )
    }

    private func headerRow(
        datasetName: String,
        presentation: DatasetIndexingPresentation,
        toggleSystemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(for: presentation))
                .frame(width: 18, height: 18)

            Text(datasetName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .compactStatusText(minimumScaleFactor: 0.76)

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                Text("100% · ~88m 88s")
                    .font(.caption2)
                    .monospacedDigit()
                    .compactStatusText(minimumScaleFactor: 0.72)
                    .hidden()

                Text(presentation.progressText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(secondaryTextColor)
                    .compactStatusText(minimumScaleFactor: 0.72)
            }

            Image(systemName: toggleSystemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    private func statusRow(presentation: DatasetIndexingPresentation) -> some View {
        HStack(spacing: 6) {
            Text(presentation.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleColor(for: presentation))
                .compactStatusText(minimumScaleFactor: 0.78)

            Text("•")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(presentation.message)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
                .compactStatusText(minimumScaleFactor: 0.78)
        }
    }

    @ViewBuilder
    private func actionRow(for banner: PresentedBanner, presentation: DatasetIndexingPresentation) -> some View {
        switch presentation.actionState {
        case .none:
            Color.clear
        case .cancelOnly:
            HStack(spacing: 8) {
                actionButton(
                    title: String(localized: "Stop", locale: locale),
                    systemImage: "xmark.circle.fill",
                    role: .destructive
                ) {
                    datasetManager.cancelProcessingForID(banner.dataset.datasetID)
                }

                Spacer(minLength: 0)
            }
        case .startAndCancel:
            HStack(spacing: 8) {
                actionButton(
                    title: String(localized: "Confirm and Start Embedding", locale: locale),
                    systemImage: "play.fill",
                    role: nil
                ) {
                    if isPluggedIn() {
                        datasetManager.startEmbeddingForID(banner.dataset.datasetID)
                    } else {
                        showBatteryConfirm = true
                    }
                }
                .confirmationDialog(
                    LocalizedStringKey("Proceed on battery power?"),
                    isPresented: $showBatteryConfirm,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedStringKey("Proceed")) {
                        datasetManager.startEmbeddingForID(banner.dataset.datasetID)
                    }
                    Button(LocalizedStringKey("Cancel"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("Embedding is resource intensive. For best performance, plug in your device. Do you want to proceed on battery?"))
                }

                actionButton(
                    title: String(localized: "Stop", locale: locale),
                    systemImage: "xmark.circle.fill",
                    role: .destructive
                ) {
                    showCancelConfirm = true
                }
                .confirmationDialog(
                    LocalizedStringKey("Cancel Embedding?"),
                    isPresented: $showCancelConfirm,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedStringKey("Cancel Embedding"), role: .destructive) {
                        datasetManager.cancelProcessingForID(banner.dataset.datasetID)
                    }
                    Button(LocalizedStringKey("Continue"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("You can restart this process in the dataset details at any time."))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .compactStatusText(minimumScaleFactor: 0.72)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func syncPresentedBanner() {
        dismissTask?.cancel()

        if let activeBanner {
            let previousDatasetID = presentedBanner?.dataset.datasetID
            presentedBanner = activeBanner
            if previousDatasetID != activeBanner.dataset.datasetID || shouldAutoExpand(for: activeBanner.status) {
                isCollapsed = false
            }
            if !showBanner {
                DispatchQueue.main.async {
                    showBanner = true
                }
            }

            if activeBanner.status.stage == .completed || activeBanner.status.stage == .failed {
                scheduleDismiss(after: activeBanner.status.stage == .completed ? 1.4 : 1.8)
            }
            return
        }

        guard let lingering = presentedBanner else {
            showBanner = false
            return
        }

        if lingering.status.stage == .completed || lingering.status.stage == .failed {
            scheduleDismiss(after: lingering.status.stage == .completed ? 1.2 : 1.6)
        } else {
            dismissCurrentBanner()
        }
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            dismissCurrentBanner()
        }
    }

    private func dismissCurrentBanner() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            showBanner = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            presentedBanner = nil
            isCollapsed = false
        }
    }

    private func collapseBanner() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isCollapsed = true
        }
    }

    private func expandBanner() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isCollapsed = false
        }
    }

    private func shouldAutoExpand(for status: DatasetProcessingStatus) -> Bool {
        switch DatasetIndexingPresentation.make(for: status, locale: locale).actionState {
        case .startAndCancel:
            return true
        case .none:
            return status.stage == .completed || status.stage == .failed
        case .cancelOnly:
            return false
        }
    }

    private func collapsedProgressText(
        for banner: PresentedBanner,
        presentation: DatasetIndexingPresentation
    ) -> String {
        switch banner.status.stage {
        case .completed, .failed:
            return presentation.progressText
        case .extracting, .compressing, .embedding:
            return "\(Int(max(0, min(1, banner.status.progress)) * 100))%"
        }
    }

    private func iconColor(for presentation: DatasetIndexingPresentation) -> Color {
        switch presentation.tone {
        case .active:
            return Color(red: 0.07, green: 0.56, blue: 1.0)
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }

    private func titleColor(for presentation: DatasetIndexingPresentation) -> Color {
        switch presentation.tone {
        case .active:
            return primaryTextColor
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }

    private func successTrackColor(for presentation: DatasetIndexingPresentation) -> Color {
        switch presentation.tone {
        case .success:
            return .green.opacity(0.28)
        case .failure:
            return .orange.opacity(0.28)
        case .active:
            return .clear
        }
    }

    private var primaryTextColor: Color {
        #if os(macOS)
        Color(nsColor: .labelColor)
        #else
        Color.primary
        #endif
    }

    private var secondaryTextColor: Color {
        #if os(macOS)
        Color(nsColor: .secondaryLabelColor)
        #else
        Color.secondary
        #endif
    }
}

private struct PresentedBanner: Equatable {
    let dataset: LocalDataset
    let status: DatasetProcessingStatus
}

private struct BannerSignature: Equatable {
    let datasetID: String
    let stage: DatasetProcessingStage
    let progressStep: Int
    let message: String
}

@MainActor
private func isPluggedIn() -> Bool {
    #if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
    #else
    return true
    #endif
}
