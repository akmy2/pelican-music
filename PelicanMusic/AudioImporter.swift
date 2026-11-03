import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Copy mode asks the provider to materialize cloud files before returning URLs.
struct AudioImporter: UIViewControllerRepresentable {
    var folders = false
    var onSelection: ([URL]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Some providers advertise MP3/M4A as generic data rather than UTType.audio.
        // Validate the actual file after copying instead of hiding those documents.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folders ? [.folder] : [.item], asCopy: !folders)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioImporter
        init(parent: AudioImporter) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onSelection(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onCancel() }
    }
}
