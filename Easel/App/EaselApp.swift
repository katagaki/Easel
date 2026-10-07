import SwiftUI

@main
struct EaselApp: App {
    @State private var photoEditLauncher = PhotoEditLauncher()

    var body: some Scene {
        DocumentGroup(newDocument: EaselDocument()) { configuration in
            DocumentView(document: configuration.$document, fileURL: configuration.fileURL)
        }

        DocumentGroupLaunchScene("Launch.Title") {
            NewDocumentButton("Launch.NewImage")
            Button("Launch.EditPhoto", systemImage: "photo.on.rectangle.angled") {
                photoEditLauncher.isPicking = true
            }
            .accessibilityIdentifier("editPhoto")
        } background: {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.mix(with: .purple, by: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .modifier(PhotoEditPresenter(launcher: photoEditLauncher))
        }
    }
}
