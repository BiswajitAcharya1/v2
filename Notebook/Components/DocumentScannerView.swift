import SwiftUI
import PhotosUI
import VisionKit

struct DocumentScannerView: View {
    var onScan: @MainActor ([UIImage]) -> Void
    var onCancel: @MainActor () -> Void = {}

    var body: some View {
        Group {
            if VNDocumentCameraViewController.isSupported {
                DocumentCameraRepresentable(onScan: onScan, onCancel: onCancel)
                    .ignoresSafeArea()
            } else {
                PhotoImportScannerFallback(onScan: onScan, onCancel: onCancel)
            }
        }
    }
}

private struct DocumentCameraRepresentable: UIViewControllerRepresentable {
    var onScan: @MainActor ([UIImage]) -> Void
    var onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let onScan: @MainActor ([UIImage]) -> Void
        private let onCancel: @MainActor () -> Void

        init(onScan: @escaping @MainActor ([UIImage]) -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        @MainActor
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true)
            onScan(images)
        }

        @MainActor
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        @MainActor
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}

@MainActor
private struct PhotoImportScannerFallback: View {
    var onScan: @MainActor ([UIImage]) -> Void
    var onCancel: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isLoading = false
    @State private var glow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.075),
                    Color(red: 0.24, green: 0.23, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Button {
                        Haptics.softTap()
                        dismiss()
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.82), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(NotebookTheme.paper)
                        .frame(width: 290, height: 390)
                        .overlay {
                            PaperRules()
                                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        }
                        .shadow(color: .black.opacity(0.28), radius: 26, y: 18)

                    if let image = selectedImages.first {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 252, height: 334)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(.white.opacity(0.52), lineWidth: 1)
                            }
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(width: 72, height: 72)
                                .background(.white.opacity(0.62), in: Circle())
                            Text("choose note images")
                                .font(.system(.title3, design: .serif, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                        }
                    }

                    ScannerFallbackSweep(active: glow || isLoading)
                        .frame(width: 254, height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .rotation3DEffect(.degrees(glow ? 2.4 : -2.4), axis: (x: 0.2, y: 1, z: 0), perspective: 0.78)

                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 12, matching: .images) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("select notes")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white.opacity(0.82), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    if !selectedImages.isEmpty {
                        ScannerFallbackPageRail(images: selectedImages)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    Button {
                        guard !selectedImages.isEmpty else { return }
                        Haptics.success()
                        onScan(selectedImages)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isLoading ? "hourglass" : "viewfinder")
                                .font(.system(size: 15, weight: .bold))
                            Text(isLoading ? "reading" : scanButtonTitle)
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedImages.isEmpty ? NotebookTheme.ink.opacity(0.38) : NotebookTheme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedImages.isEmpty || isLoading)
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 10)
            }
        }
        .task(id: selectedItemsSignature) {
            await loadSelectedImages()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private var selectedItemsSignature: String {
        selectedItems
            .enumerated()
            .map { index, item in item.itemIdentifier ?? "image-\(index)" }
            .joined(separator: "|")
    }

    private var scanButtonTitle: String {
        if selectedImages.count <= 1 { return "scan page" }
        return "scan \(selectedImages.count) pages"
    }

    @MainActor
    private func loadSelectedImages() async {
        guard !selectedItems.isEmpty else {
            selectedImages = []
            return
        }
        isLoading = true
        var images: [UIImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        selectedImages = images
        isLoading = false
    }
}

private struct ScannerFallbackPageRail: View {
    let images: [UIImage]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(images.prefix(5).enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.62), lineWidth: 0.8)
                    }
                    .rotationEffect(.degrees(Double(index - 2) * 1.7))
                    .offset(y: CGFloat(abs(index - 2)) * 1.5)
            }

            if images.count > 5 {
                Text("+\(images.count - 5)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(width: 38, height: 48)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.13), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
        .accessibilityLabel("\(images.count) pages selected")
    }
}

private struct ScannerFallbackSweep: View {
    var active: Bool

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, .white.opacity(0.32), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.82, height: 24)
            .blur(radius: 6)
            .rotationEffect(.degrees(-12))
            .offset(x: active ? proxy.size.width * 0.3 : -proxy.size.width * 0.5, y: active ? proxy.size.height * 0.62 : proxy.size.height * 0.18)
            .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: active)
        }
        .allowsHitTesting(false)
    }
}
