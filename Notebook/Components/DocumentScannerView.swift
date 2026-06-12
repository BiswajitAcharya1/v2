import SwiftUI
import PhotosUI
import VisionKit

struct DocumentScannerView: View {
    var preferPhotoImport = false
    var onScan: @MainActor ([UIImage]) -> Void
    var onCancel: @MainActor () -> Void = {}

    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            PhotoImportScannerFallback(onScan: onScan, onCancel: onCancel)
            #else
            if preferPhotoImport {
                PhotoImportScannerFallback(onScan: onScan, onCancel: onCancel)
            } else if VNDocumentCameraViewController.isSupported {
                ZStack {
                    DocumentCameraRepresentable(onScan: onScan, onCancel: onCancel)
                        .ignoresSafeArea()
                    NativeScannerChrome()
                        .allowsHitTesting(false)
                }
            } else {
                PhotoImportScannerFallback(onScan: onScan, onCancel: onCancel)
            }
            #endif
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
    @State private var scanLight = false
    @State private var closeRotation = 0.0

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
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.82), in: Circle())
                            .rotationEffect(.degrees(closeRotation))
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
                        .frame(width: 292, height: 402)
                        .overlay {
                            PaperRules()
                                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        }
                        .shadow(color: .black.opacity(0.28), radius: 26, y: 18)

                    if let image = selectedImages.first {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 254, height: 346)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(.white.opacity(0.52), lineWidth: 1)
                            }
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(width: 52, height: 52)
                                .background(.white.opacity(0.62), in: Circle())
                            Text("choose note images")
                                .font(.system(.title3, design: .serif, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                        }
                    }

                    ScannerFallbackSweep(active: glow || isLoading)
                        .frame(width: 254, height: 346)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    ScannerExtractionHUD(active: scanLight || !selectedImages.isEmpty)
                        .frame(width: 254, height: 346)
                        .opacity(selectedImages.isEmpty ? 0.72 : 1)
                }
                .rotation3DEffect(.degrees(glow ? 1.2 : -1.2), axis: (x: 0.2, y: 1, z: 0), perspective: 0.78)

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
                        .frame(height: 48)
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
                        .frame(height: 48)
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
            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                scanLight = true
            }
        }
    }

    private func close() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            closeRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            dismiss()
            onCancel()
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

private struct NativeScannerChrome: View {
    @State private var active = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                ScannerFocusFrame(active: active)
                    .frame(height: 426)
                    .padding(.horizontal, 28)

                Text("hold steady")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.black.opacity(0.26), in: Capsule())
                    .overlay {
                        Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7)
                    }
                    .padding(.bottom, 22)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct ScannerFocusFrame: View {
    var active: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.26), lineWidth: 1)
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 32, style: .continuous))

                ScannerCornerMarks()
                    .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                    .padding(13)

                LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.72, height: 24)
                    .blur(radius: 7)
                    .rotationEffect(.degrees(-10))
                    .offset(x: active ? width * 0.18 : -width * 0.32, y: active ? height * 0.18 : -height * 0.14)
                    .blendMode(.screen)
            }
        }
    }
}

private struct ScannerCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 36
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct ScannerExtractionHUD: View {
    var active: Bool

    var body: some View {
        ZStack {
            ScannerCornerMarks()
                .stroke(NotebookTheme.ink.opacity(0.42), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .padding(8)

            VStack {
                Spacer()
                Capsule()
                    .fill(NotebookTheme.ink.opacity(active ? 0.26 : 0.14))
                    .frame(width: active ? 92 : 64, height: 5)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: active)
                .padding(.bottom, 12)
            }
        }
        .allowsHitTesting(false)
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
