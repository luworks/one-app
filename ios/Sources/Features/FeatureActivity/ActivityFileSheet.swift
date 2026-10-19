import SwiftUI
import UIKit

/// UIKit's share sheet for a file, so the export can go to Files, AirDrop or Mail (the system Files exporter needs no iCloud).
struct ActivityFileSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
