import SwiftUI

/// A document window: the editor, with sharing and the file's title menu.
struct DocumentView: View {
    @Binding var document: EaselDocument
    /// Where the file lives, which is what converting it moves.
    var fileURL: URL?
    @State private var errorMessage: String?
    @State private var savedToPhotos = false

    private var name: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? String(localized: "Export.DefaultName")
    }

    var body: some View {
        EditorView(composition: $document.composition)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu { titleMenu }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { exportMenu }
            }
            .alert(
                "Alert.Error.Title",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("Common.OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: savedToPhotos)
    }

    private var exportMenu: some View {
        Menu {
            Section("Export.ShareAs") {
                ForEach(CompositionExport.Format.allCases) { format in
                    ShareLink(
                        item: CompositionExport(composition: document.composition, name: name, format: format),
                        preview: SharePreview(name, image: Image(systemName: "photo"))
                    ) {
                        Text(format.label)
                    }
                }
            }
            Button("Export.SaveToPhotos", systemImage: "photo.badge.plus") {
                let composition = document.composition
                Task {
                    do {
                        try await CompositionExport.saveToPhotos(composition)
                        savedToPhotos.toggle()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } label: {
            Label("Toolbar.Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("export")
    }

    /// Renaming, and — for a plain picture, which flattens when saved —
    /// turning the file into an Easel image that keeps its layers.
    @ViewBuilder
    private var titleMenu: some View {
        RenameButton()
        if let fileURL, DocumentConversion.canConvert(fileURL) {
            Section {
                Button("TitleMenu.ConvertToEasel", systemImage: "square.3.layers.3d") {
                    let composition = document.composition
                    Task {
                        do {
                            _ = try await DocumentConversion.convert(fileAt: fileURL, composition: composition)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } footer: {
                Text("TitleMenu.ConvertToEasel.Footer")
            }
        }
    }
}
