import Foundation
import Testing
@testable import Easel

@Suite("Keep Layers")
struct DocumentConversionTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func picturesAreReplaced() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = folder.appending(path: "Photo.png")
        try ImageCodec.encode(TestImages.solid(.white, width: 4, height: 4), as: .png).write(to: picture)
        let easel = try await DocumentConversion.convert(fileAt: picture, composition: .blank())
        #expect(easel.lastPathComponent == "Photo.easel")
        #expect(FileManager.default.fileExists(atPath: easel.path))
        #expect(!FileManager.default.fileExists(atPath: picture.path))
    }

    /// Nothing edited in a Pixelmator or large Photoshop file can be saved
    /// back to it, so the original stays beside the Easel image.
    @Test func pixelmatorAndLargePhotoshopFilesAreKept() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Sketch.pxd", "Poster.psb"] {
            let original = folder.appending(path: name)
            let contents = Data(name.utf8)
            try contents.write(to: original)
            let easel = try await DocumentConversion.convert(fileAt: original, composition: .blank())
            #expect(easel.pathExtension == "easel")
            #expect(try CompositionArchive.composition(from: FileWrapper(url: easel)).size == Composition.blank().size)
            #expect(try Data(contentsOf: original) == contents)
        }
    }
}
