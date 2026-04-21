import Foundation
import Testing
import ZIPFoundation
@testable import ReViser
import UniformTypeIdentifiers

@Suite("ReViser")
struct ReViserTests {
    @Test
    func sectionsOverviewOrderMetadata() {
        #expect(SectionsOverviewOrder.row.label == "Left to right")
        #expect(SectionsOverviewOrder.row.systemImage == "arrow.left.arrow.right")
        #expect(SectionsOverviewOrder.column.label == "Top to bottom")
        #expect(SectionsOverviewOrder.column.systemImage == "arrow.up.arrow.down")
    }

    @Test
    @MainActor
    func loadDocumentFromPlainTextCreatesProject() async throws {
        let model = AppModel()
        let fileURL = try makeTemporaryFile(extension: "txt", contents: "Draft line one\nDraft line two")

        await model.loadDocument(from: fileURL)

        #expect(model.importedFileName == fileURL.lastPathComponent)
        #expect(model.importedText == "Draft line one\nDraft line two")
        #expect(model.projects.count == 1)
        #expect(model.projects[0].title == fileURL.deletingPathExtension().lastPathComponent)
        #expect(model.projects[0].sections.count == 1)
        #expect(model.projects[0].sections[0].text == "Draft line one\nDraft line two")
    }

    @Test
    @MainActor
    func loadDocumentFromDocxExtractsFormattedText() async throws {
        let model = AppModel()
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:b/><w:t>Bold</w:t></w:r>
              <w:r><w:i/><w:t>Italic</w:t></w:r>
              <w:r><w:u/><w:t>Underline</w:t></w:r>
              <w:r><w:strike/><w:t>Strike</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let fileURL = try makeTemporaryDocxArchive(documentXML: xml)

        await model.loadDocument(from: fileURL)

        #expect(model.importedText.contains("**Bold**"))
        #expect(model.importedText.contains("_Italic_"))
        #expect(model.importedText.contains("__Underline__"))
        #expect(model.importedText.contains("~~Strike~~"))
        #expect(model.projects.count == 1)
        #expect(model.projects[0].sections.count == 1)
    }

    @Test
    @MainActor
    func updateProjectSectionsKeepsProjectTextInSync() {
        let model = AppModel()
        let projectID = UUID()
        model.projects = [
            AppModel.Project(
                id: projectID,
                title: "Sample",
                sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"),
                createdAt: .now,
                lastModified: .now,
                text: "",
                sections: [
                    Section(id: UUID(), text: "Alpha"),
                    Section(id: UUID(), text: "Beta")
                ]
            )
        ]

        let replacementSections = [
            Section(id: UUID(), text: "One"),
            Section(id: UUID(), text: "Two"),
            Section(id: UUID(), text: "Three")
        ]

        model.updateProjectSections(id: projectID, sections: replacementSections)

        #expect(model.projects[0].sections == replacementSections)
        #expect(model.projects[0].text == "OneTwoThree")
    }

    @Test
    @MainActor
    func updateProjectTextCreatesFallbackSectionWhenNeeded() {
        let model = AppModel()
        let projectID = UUID()
        model.projects = [
            AppModel.Project(
                id: projectID,
                title: "Empty",
                sourceURL: URL(fileURLWithPath: "/tmp/empty.txt"),
                createdAt: .now,
                lastModified: .now,
                text: "",
                sections: []
            )
        ]

        model.updateProjectText(id: projectID, text: "Revised manuscript")

        #expect(model.projects[0].text == "Revised manuscript")
        #expect(model.projects[0].sections.count == 1)
        #expect(model.projects[0].sections[0].text == "Revised manuscript")
    }

    @Test
    @MainActor
    func graveyardRestoreAndPermanentRemoval() {
        let model = AppModel()
        let projectID = UUID()
        let first = Section(id: UUID(), text: "First")
        let second = Section(id: UUID(), text: "Second")
        let third = Section(id: UUID(), text: "Third")

        model.projects = [
            AppModel.Project(
                id: projectID,
                title: "Draft",
                sourceURL: URL(fileURLWithPath: "/tmp/draft.txt"),
                createdAt: .now,
                lastModified: .now,
                text: "FirstSecondThird",
                sections: [first, second, third]
            )
        ]

        model.moveSectionToGraveyard(projectID: projectID, section: second, originalIndex: 1)
        #expect(model.sectionGraveyard.count == 1)
        #expect(model.sectionGraveyard[0].section == second)

        let deletedID = model.sectionGraveyard[0].id
        model.updateProjectSections(id: projectID, sections: [first, third])
        model.restoreSectionFromGraveyard(deletedID)

        #expect(model.sectionGraveyard.count == 0)
        #expect(model.projects[0].sections == [first, second, third])

        model.moveSectionToGraveyard(projectID: projectID, section: second, originalIndex: 1)
        let permanentID = model.sectionGraveyard[0].id
        model.removeFromGraveyardPermanently(permanentID)

        #expect(model.sectionGraveyard.isEmpty)
    }

    @Test
    @MainActor
    func filteredProjectsAreSearchableAndSortedByRecentChange() {
        let model = AppModel()
        let oldProject = AppModel.Project(
            id: UUID(),
            title: "Alpha Draft",
            sourceURL: URL(fileURLWithPath: "/tmp/alpha.txt"),
            createdAt: .now.addingTimeInterval(-1000),
            lastModified: .now.addingTimeInterval(-1000),
            text: "Alpha",
            sections: [Section(id: UUID(), text: "Alpha")]
        )
        let newProject = AppModel.Project(
            id: UUID(),
            title: "Beta Draft",
            sourceURL: URL(fileURLWithPath: "/tmp/beta.txt"),
            createdAt: .now,
            lastModified: .now,
            text: "Beta",
            sections: [Section(id: UUID(), text: "Beta")]
        )

        model.projects = [oldProject, newProject]

        #expect(model.filteredProjects.first?.title == "Beta Draft")

        model.searchQuery = "alpha"
        #expect(model.filteredProjects.map(\.title) == ["Alpha Draft"])
    }

    @Test
    @MainActor
    func previewTextPrefersRestitchedSectionsOverProjectText() {
        let model = AppModel()
        let project = AppModel.Project(
            id: UUID(),
            title: "Preview",
            sourceURL: URL(fileURLWithPath: "/tmp/preview.txt"),
            createdAt: .now,
            lastModified: .now,
            text: "Fallback project text",
            sections: [
                Section(id: UUID(), text: "First section "),
                Section(id: UUID(), text: "Second section")
            ]
        )

        #expect(model.previewText(for: project, limit: 100) == "First section Second section")
    }

    @Test
    @MainActor
    func supportedContentTypesIncludeCommonManuscriptFormats() async {
        let supportedContentTypes = await MainActor.run {
            let model = AppModel()
            return model.supportedContentTypes
        }

        #expect(supportedContentTypes.contains(.plainText))
        #expect(supportedContentTypes.contains(.rtf))
        #expect(supportedContentTypes.contains(.pdf))
        #expect(supportedContentTypes.contains(UTType(filenameExtension: "docx")!))
    }

    @Test
    func docxFormatterConvertsCommonFormattingMarkers() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:b/><w:t>Bold</w:t></w:r>
              <w:r><w:i/><w:t>Italic</w:t></w:r>
              <w:r><w:u/><w:t>Underline</w:t></w:r>
              <w:r><w:strike/><w:t>Strike</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>Plain</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let formatted = DocxFormatter().convert(documentXML: xml)

        #expect(formatted.contains("**Bold**"))
        #expect(formatted.contains("_Italic_"))
        #expect(formatted.contains("__Underline__"))
        #expect(formatted.contains("~~Strike~~"))
        #expect(formatted.contains("\t"))
        #expect(formatted.contains("Plain"))
    }

    private func makeTemporaryFile(extension fileExtension: String, contents: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func makeTemporaryDocxArchive(documentXML: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("docx")
        let archive = try Archive(url: fileURL, accessMode: .create)
        let data = Data(documentXML.utf8)

        try archive.addEntry(
            with: "word/document.xml",
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: position..<position + size)
        }

        return fileURL
    }
}
