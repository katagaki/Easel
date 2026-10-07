import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Easel's own layered document, declared in Info.plist.
    static let easelImage = UTType(exportedAs: "com.tsubuzaki.Easel.image", conformingTo: .package)
    /// Photoshop documents, declared by the system.
    static let photoshopImage = UTType("com.adobe.photoshop-image") ?? UTType(importedAs: "com.adobe.photoshop-image")
    /// Pixelmator Pro documents, declared in Info.plist.
    static let pixelmatorProImage = UTType(importedAs: "com.pixelmatorteam.pixelmator.document.pro")
}

/// The app's document: a layered composition, kept as an `.easel` package,
/// or a plain picture file edited where it lies — which keeps its format
/// and so is flattened when it is saved.
struct EaselDocument: FileDocument {
    /// Photoshop and Pixelmator Pro files open but are not written back:
    /// Keep Layers turns them into an Easel image.
    static let readableContentTypes: [UTType] = [.easelImage, .png, .jpeg, .heic, .photoshopImage, .pixelmatorProImage]
    static let writableContentTypes: [UTType] = [.easelImage, .png, .jpeg, .heic]

    var composition: Composition

    init() {
        composition = .blank()
    }

    init(composition: Composition) {
        self.composition = composition
    }

    init(configuration: ReadConfiguration) throws {
        if configuration.contentType.conforms(to: .pixelmatorProImage) {
            composition = try PXDReader.composition(from: configuration.file)
        } else if configuration.file.isDirectory {
            composition = try CompositionArchive.composition(from: configuration.file)
        } else if configuration.contentType.conforms(to: .photoshopImage) {
            guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            composition = try PSDReader.composition(from: data)
        } else {
            guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            composition = Composition(
                image: try ImageCodec.decode(data), name: String(localized: "Layer.DefaultName.Background")
            )
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Only a picture format named outright is flattened; anything else,
        // including a type the system has not resolved yet, keeps the layers.
        guard let type = Self.pictureType(for: configuration.contentType) else {
            return try CompositionArchive.fileWrapper(for: composition)
        }
        let image = CompositionRenderer.render(composition)
        return FileWrapper(regularFileWithContents: try ImageCodec.encode(image, as: type))
    }

    private static func pictureType(for contentType: UTType) -> UTType? {
        [UTType.png, .heic, .jpeg].first { contentType.conforms(to: $0) }
    }
}
