import SwiftUI
import PhotosUI

/// The single control for attaching a photo to a walk, used both while
/// recording and afterwards on the summary and detail screens.
///
/// Offers the camera when one is available (never in the Simulator) and the
/// photo library always, behind one consistent menu, so "add a walk photo"
/// looks and behaves the same everywhere it appears.
public struct AddWalkPhotoButton: View {
    private let label: String
    private let symbolName: String
    private let onCapture: (Data) async -> Void

    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showsLibraryPicker = false

    public init(
        label: String = "Add Photo",
        symbolName: String = "camera.fill",
        onCapture: @escaping (Data) async -> Void
    ) {
        self.label = label
        self.symbolName = symbolName
        self.onCapture = onCapture
    }

    public var body: some View {
        Menu {
            #if os(iOS)
            if CameraAvailability.isAvailable {
                Button("Take Photo", systemImage: "camera") { showsCamera = true }
            }
            #endif
            Button("Choose from Library", systemImage: "photo.on.rectangle") {
                showsLibraryPicker = true
            }
        } label: {
            Label(label, systemImage: symbolName)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView(
                onCapture: { data in
                    showsCamera = false
                    Task { await onCapture(data) }
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        #endif
        .photosPicker(isPresented: $showsLibraryPicker, selection: $libraryItem, matching: .images)
        .task(id: libraryItem) {
            guard let libraryItem else { return }
            defer { self.libraryItem = nil }
            guard let data = try? await libraryItem.loadTransferable(type: Data.self) else { return }
            await onCapture(data)
        }
    }
}
