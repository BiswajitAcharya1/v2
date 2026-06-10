import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: @MainActor ([UIImage]) -> Void
    var onCancel: @MainActor () -> Void = {}

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
