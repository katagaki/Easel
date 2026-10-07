import SwiftUI

@main
struct EaselApp: App {
    @State private var photoEditLauncher = PhotoEditLauncher()

    var body: some Scene {
        DocumentGroup(newDocument: EaselDocument()) { configuration in
            DocumentView(document: configuration.$document, fileURL: configuration.fileURL)
        }

        // An empty title, so the tool wall carries the header on its own.
        // With no title at all, the scene falls back to the app's name.
        DocumentGroupLaunchScene(Text(verbatim: "")) {
            NewDocumentButton("Launch.NewImage")
            Button("Launch.EditPhoto", systemImage: "photo.on.rectangle.angled") {
                photoEditLauncher.isPicking = true
            }
            .accessibilityIdentifier("editPhoto")
        } background: {
            DocumentLaunchBackground()
                .modifier(PhotoEditPresenter(launcher: photoEditLauncher))
        } backgroundAccessoryView: { geometry in
            DocumentLaunchToolWall(geometry: geometry)
        }
    }
}
