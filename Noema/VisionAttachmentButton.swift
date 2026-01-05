#if os(iOS) || os(macOS) || os(visionOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS)
import Photos
#endif
#if os(macOS)
import AppKit
#endif

/// Circular (or rounded, on visionOS) control that mirrors the chat globe button but
/// arms image attachments instead. Presents a platform-appropriate picker when the
/// active model supports vision input and honors the five-image cap.
struct VisionAttachmentButton: View {
    @EnvironmentObject private var vm: ChatVM
#if os(macOS)
    @State private var isProcessingImport = false
#else
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
#if os(iOS)
    @State private var showAttachmentTray = false
    @State private var showCameraCapture = false
    @State private var recentAssets: [PHAsset] = []
    @State private var thumbnailCache: [String: UIImage] = [:]
    @State private var isLoadingRecents = false
    @State private var photoAccessDenied = false
    @State private var cameraUnavailableAlert = false
#endif
#endif
    @State private var showDisabledReason = false

#if os(macOS)
    private let size: CGFloat = 24
#else
    private let size: CGFloat = 28
#endif

#if os(visionOS)
    private let visionButtonSize = CGSize(width: 78, height: 48)
    private let visionCornerRadius: CGFloat = 24
#endif

    private let maxImages = 5

    var body: some View {
        Group {
#if os(macOS)
            Button(action: handleTap) {
                buttonContent
            }
#else
            Button(action: handleTap) {
                buttonContent
            }
            .photosPicker(
                isPresented: $showPicker,
                selection: $pickerItems,
                maxSelectionCount: max(0, remainingSlots),
                matching: .images
            )
            .onChangeCompat(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPickedItems(items) }
            }
#if os(iOS)
            .sheet(isPresented: $showAttachmentTray) {
                AttachmentTray(
                    recentAssets: recentAssets,
                    thumbnails: thumbnailCache,
                    isLoading: isLoadingRecents,
                    remainingSlots: remainingSlots,
                    photoAccessGranted: !photoAccessDenied,
                    onCamera: {
                        showAttachmentTray = false
                        openCamera()
                    },
                    onAllPhotos: {
                        showAttachmentTray = false
                        showPicker = true
                    },
                    onAssetTap: { asset in
                        Task { await handleRecentAssetTap(asset) }
                    }
                )
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
            }
            .fullScreenCover(isPresented: $showCameraCapture) {
                CameraCaptureView(
                    onCapture: { image in
                        showCameraCapture = false
                        Task { await vm.savePendingImage(image) }
                    },
                    onCancel: { showCameraCapture = false }
                )
                .ignoresSafeArea()
            }
#endif
#endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Attach Photos"))
        .accessibilityHint(Text(accessibilityHintText))
        .help(helpText)
        .alert("Vision Attachments Unavailable", isPresented: $showDisabledReason) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(disabledReason)
        }
#if os(iOS)
        .alert("Photo Access Needed", isPresented: $photoAccessDenied) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") { openAppSettings() }
        } message: {
            Text("Allow photo access to show your recent pictures or use All Photos.")
        }
        .alert("Camera Unavailable", isPresented: $cameraUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This device doesn't have a camera available. Try picking from All Photos instead.")
        }
#endif
    }

    @ViewBuilder
    private var buttonContent: some View {
        Image(systemName: iconName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(foregroundColor)
#if os(visionOS)
            .frame(width: visionButtonSize.width, height: visionButtonSize.height)
#else
            .padding(10)
#endif
            .background(buttonBackground)
            .overlay(alignment: .topTrailing) {
                if vm.pendingImageURLs.count > 0 {
                    BadgeView(count: vm.pendingImageURLs.count)
                        .offset(x: 4, y: -4)
                }
            }
            .opacity(isDisabled ? 0.5 : 1.0)
    }

    private var iconName: String {
        if vm.pendingImageURLs.count > 0 {
            return "photo.stack.fill"
        }
        return "photo.on.rectangle"
    }

    private var remainingSlots: Int {
        max(0, maxImages - vm.pendingImageURLs.count)
    }

    private var isDisabled: Bool {
        guard UIConstants.showMultimodalUI else { return true }
        if remainingSlots == 0 { return true }
        if !vm.supportsImageInput { return true }
        if !vm.modelLoaded { return true }
        return false
    }

    private var foregroundColor: Color {
        if isDisabled { return .secondary }
        return vm.pendingImageURLs.isEmpty ? .primary : Color.white
    }

    private var backgroundFill: Color {
        if isDisabled { return Color.gray.opacity(0.12) }
        if vm.pendingImageURLs.isEmpty { return Color(.systemBackground).opacity(0.9) }
        return Color.visionAccent
    }

    private var borderColor: Color {
        if vm.pendingImageURLs.isEmpty {
            return isDisabled ? Color.gray.opacity(0.2) : Color.gray.opacity(0.25)
        }
        return .clear
    }

    private var glowColor: Color {
        if vm.pendingImageURLs.isEmpty { return .clear }
        return Color.visionAccent.opacity(0.45)
    }

#if os(visionOS)
    @ViewBuilder
    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: visionCornerRadius, style: .continuous)
            .fill(backgroundFill)
            .overlay(
                RoundedRectangle(cornerRadius: visionCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: vm.pendingImageURLs.isEmpty ? 0.75 : 0)
            )
            .shadow(color: glowColor, radius: vm.pendingImageURLs.isEmpty ? 0 : 12, y: vm.pendingImageURLs.isEmpty ? 0 : 6)
    }
#else
    @ViewBuilder
    private var buttonBackground: some View {
        Circle()
            .fill(backgroundFill)
            .overlay(
                Circle()
                    .strokeBorder(borderColor, lineWidth: vm.pendingImageURLs.isEmpty ? 0.75 : 0)
            )
            .shadow(color: glowColor, radius: vm.pendingImageURLs.isEmpty ? 0 : 8)
    }
#endif

    private var disabledReason: String {
        if !UIConstants.showMultimodalUI {
            return "Vision features are disabled by configuration."
        }
        if !vm.modelLoaded {
            return "Load a model before attaching images."
        }
        if !vm.supportsImageInput {
            return "The active model can't process images."
        }
        if remainingSlots == 0 {
            return "You've already attached the maximum of \(maxImages) images."
        }
        return "Vision attachments are currently unavailable."
    }

    private var accessibilityHintText: String {
        if isDisabled {
            return "Disabled: \(disabledReason)"
        }
        return vm.pendingImageURLs.isEmpty ? "Add photos to your next message." : "Add more photos or review attached images."
    }

    private var helpText: String {
        if isDisabled { return disabledReason }
        return "Attach up to \(maxImages) images (order preserved). No resizing needed — llama.cpp preprocesses images automatically."
    }

    private func handleTap() {
        guard !isDisabled else {
            showDisabledReason = true
            return
        }
#if os(macOS)
        if !isProcessingImport {
            isProcessingImport = true
            Task { await presentOpenPanel() }
        }
#elseif os(iOS)
        Task { await loadRecentsIfNeeded() }
        showAttachmentTray = true
#else
        showPicker = true
#endif
    }

#if os(macOS)
    @MainActor
    private func presentOpenPanel() async {
        defer { isProcessingImport = false }
        let remaining = remainingSlots
        guard remaining > 0 else { return }

        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "heif", "webp"]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = remaining > 1 ? "Choose Images" : "Choose Image"

        let response = panel.runModal()
        guard response == .OK else { return }
        let picks = panel.urls.prefix(remaining)
        for url in picks {
            if let image = UIImage(contentsOfFile: url.path) {
                await vm.savePendingImage(image)
            }
        }
    }
#else
#if os(iOS)
    @MainActor
    private func loadRecentsIfNeeded() async {
        guard remainingSlots > 0 else { return }
        guard recentAssets.isEmpty else { return }
        let authorized = await requestPhotoAuthorization()
        if !authorized {
            photoAccessDenied = true
            return
        }
        photoAccessDenied = false
        await fetchRecentAssets()
    }

    private func requestPhotoAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            return false
        }
    }

    @MainActor
    private func fetchRecentAssets() async {
        guard !isLoadingRecents else { return }
        isLoadingRecents = true
        thumbnailCache.removeAll()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 10

        let fetched = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        recentAssets = assets

        let manager = PHCachingImageManager()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.isSynchronous = false
        let targetSize = CGSize(width: 220, height: 220)

        for asset in assets {
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { image, _ in
                guard let image else { return }
                Task { @MainActor in
                    thumbnailCache[asset.localIdentifier] = image
                }
            }
        }

        isLoadingRecents = false
    }

    private func handleRecentAssetTap(_ asset: PHAsset) async {
        guard remainingSlots > 0 else { return }
        let id = asset.localIdentifier
        if let cached = thumbnailCache[id] {
            await vm.savePendingImage(cached)
            return
        }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true
        let targetSize = CGSize(width: 1600, height: 1600)

        var selected: UIImage?
        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, _ in
            selected = image
        }
        if let selected {
            await vm.savePendingImage(selected)
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableAlert = true
            return
        }
        showCameraCapture = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
#endif
    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        let allowance = remainingSlots
        guard allowance > 0 else {
            await MainActor.run { pickerItems.removeAll() }
            return
        }
        for item in items.prefix(allowance) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await vm.savePendingImage(image)
            }
        }
        await MainActor.run { pickerItems.removeAll() }
    }
#endif
}

private struct BadgeView: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.75))
            )
            .foregroundStyle(Color.white)
    }
}

#if os(iOS)
private struct AttachmentTray: View {
    let recentAssets: [PHAsset]
    let thumbnails: [String: UIImage]
    let isLoading: Bool
    let remainingSlots: Int
    let photoAccessGranted: Bool
    let onCamera: () -> Void
    let onAllPhotos: () -> Void
    let onAssetTap: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(action: onAllPhotos) {
                    Text("All Photos")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    cameraTile

                    if isLoading {
                        ForEach(0..<6, id: \.self) { _ in placeholderTile }
                    } else if photoAccessGranted {
                        if recentAssets.isEmpty {
                            emptyTile
                        } else {
                            ForEach(recentAssets, id: \.localIdentifier) { asset in
                                if let image = thumbnails[asset.localIdentifier] {
                                    thumbnailTile(image: image) { onAssetTap(asset) }
                                } else {
                                    placeholderTile
                                        .onTapGesture { onAssetTap(asset) }
                                }
                            }
                        }
                    } else {
                        permissionTile
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraTile: some View {
        Button(action: onCamera) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
    }

    private func thumbnailTile(image: UIImage, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 96, height: 96)
            .overlay(
                ProgressView()
                    .progressViewStyle(.circular)
            )
    }

    private var emptyTile: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 190, height: 96)
            .overlay(alignment: .leading) {
                Text("No recent photos yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
    }

    @ViewBuilder
    private var permissionTile: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 180, height: 86)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow photo access to see recents.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Text("Tap All Photos to choose manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }
    }
}
#endif

#else
import SwiftUI

struct VisionAttachmentButton: View {
    var body: some View { EmptyView() }
}
#endif
