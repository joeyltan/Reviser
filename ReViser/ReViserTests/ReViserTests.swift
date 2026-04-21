import XCTest
import ZIPFoundation
@testable import ReViser
internal import UniformTypeIdentifiers

final class ReViserTests: XCTestCase {
    func testSectionsOverviewOrderMetadata() {
        XCTAssertEqual(SectionsOverviewOrder.row.label, "Left to right")
        XCTAssertEqual(SectionsOverviewOrder.row.systemImage, "arrow.left.arrow.right")
        XCTAssertEqual(SectionsOverviewOrder.column.label, "Top to bottom")
        XCTAssertEqual(SectionsOverviewOrder.column.systemImage, "arrow.up.arrow.down")
    }

    @MainActor
    func testLoadDocumentFromPlainTextCreatesProject() async throws {
        let model = AppModel()
        let fileURL = try makeTemporaryFile(extension: "txt", contents: "Draft line one\nDraft line two")

        await model.loadDocument(from: fileURL)

        XCTAssertEqual(model.importedFileName, fileURL.lastPathComponent)
        XCTAssertEqual(model.importedText, "Draft line one\nDraft line two")
        XCTAssertEqual(model.projects.count, 1)
        XCTAssertEqual(model.projects[0].title, fileURL.deletingPathExtension().lastPathComponent)
        XCTAssertEqual(model.projects[0].sections.count, 1)
        XCTAssertEqual(model.projects[0].sections[0].text, "Draft line one\nDraft line two")
    }

    @MainActor
    func testLoadDocumentFromDocxExtractsFormattedText() async throws {
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

        XCTAssertTrue(model.importedText.contains("**Bold**"))
        XCTAssertTrue(model.importedText.contains("_Italic_"))
        XCTAssertTrue(model.importedText.contains("__Underline__"))
        XCTAssertTrue(model.importedText.contains("~~Strike~~"))
        XCTAssertEqual(model.projects.count, 1)
        XCTAssertEqual(model.projects[0].sections.count, 1)
    }

    @MainActor
    func testUpdateProjectSectionsKeepsProjectTextInSync() {
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

        XCTAssertEqual(model.projects[0].sections, replacementSections)
        XCTAssertEqual(model.projects[0].text, "OneTwoThree")
    }

    @MainActor
    func testUpdateProjectTextCreatesFallbackSectionWhenNeeded() {
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

        XCTAssertEqual(model.projects[0].text, "Revised manuscript")
        XCTAssertEqual(model.projects[0].sections.count, 1)
        XCTAssertEqual(model.projects[0].sections[0].text, "Revised manuscript")
    }

    @MainActor
    func testGraveyardRestoreAndPermanentRemoval() {
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
        XCTAssertEqual(model.sectionGraveyard.count, 1)
        XCTAssertEqual(model.sectionGraveyard[0].section, second)

        let deletedID = model.sectionGraveyard[0].id
        model.updateProjectSections(id: projectID, sections: [first, third])
        model.restoreSectionFromGraveyard(deletedID)

        XCTAssertEqual(model.sectionGraveyard.count, 0)
        XCTAssertEqual(model.projects[0].sections, [first, second, third])

        model.moveSectionToGraveyard(projectID: projectID, section: second, originalIndex: 1)
        let permanentID = model.sectionGraveyard[0].id
        model.removeFromGraveyardPermanently(permanentID)

        XCTAssertTrue(model.sectionGraveyard.isEmpty)
    }

    @MainActor
    func testFilteredProjectsAreSearchableAndSortedByRecentChange() {
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

        XCTAssertEqual(model.filteredProjects.first?.title, "Beta Draft")

        model.searchQuery = "alpha"
        XCTAssertEqual(model.filteredProjects.map(\.title), ["Alpha Draft"])
    }

    @MainActor
    func testPreviewTextPrefersRestitchedSectionsOverProjectText() {
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

        XCTAssertEqual(model.previewText(for: project, limit: 100), "First section Second section")
    }

    @MainActor func testSupportedContentTypesIncludeCommonManuscriptFormats() {
        let model = AppModel()

        XCTAssertTrue(model.supportedContentTypes.contains(.plainText))
        XCTAssertTrue(model.supportedContentTypes.contains(.rtf))
        XCTAssertTrue(model.supportedContentTypes.contains(.pdf))
        XCTAssertTrue(model.supportedContentTypes.contains(UTType(filenameExtension: "docx")!))
    }

    func testDocxFormatterConvertsCommonFormattingMarkers() {
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

        XCTAssertTrue(formatted.contains("**Bold**"))
        XCTAssertTrue(formatted.contains("_Italic_"))
        XCTAssertTrue(formatted.contains("__Underline__"))
        XCTAssertTrue(formatted.contains("~~Strike~~"))
        XCTAssertTrue(formatted.contains("\t"))
        XCTAssertTrue(formatted.contains("Plain"))
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
