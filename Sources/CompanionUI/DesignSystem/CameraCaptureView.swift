import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
/// Wraps `UIImagePickerController` in camera mode.
///
/// `PhotosPicker` (the type used elsewhere for library photos) has no camera
/// mode of its own — it only ever reads from the existing library — so a live
/// capture needs this older, UIKit-only controller instead.
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        // Walk photos are casual snapshots, not documents — no crop step
        // between "take" and "it's attached to the walk".
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else {
                parent.onCancel()
                return
            }
            parent.onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

/// Whether this device can actually present a camera. False in the Simulator
/// and on iPods without one — callers use this to hide "Take Photo" rather
/// than offering a control that would fail silently when tapped.
public enum CameraAvailability {
    public static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
#endif
