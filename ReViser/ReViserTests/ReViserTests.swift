import Foundation
import Testing
import ZIPFoundation
@testable import ReViser
import UniformTypeIdentifiers
import UIKit

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
              <w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r>
              <w:r><w:rPr><w:i/></w:rPr><w:t>Italic</w:t></w:r>
              <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>Underline</w:t></w:r>
              <w:r><w:rPr><w:strike/></w:rPr><w:t>Strike</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let fileURL = try makeTemporaryDocxArchive(documentXML: xml)

        await model.loadDocument(from: fileURL)

        #expect(model.importedText == "BoldItalicUnderlineStrike\n")
        #expect(model.projects.count == 1)
        #expect(model.projects[0].sections.count == 1)
        let section = model.projects[0].sections[0]
        #expect(section.boldStyles == [TextStyleRange(location: 0, length: 4, style: "bold")])
        #expect(section.italicStyles == [TextStyleRange(location: 4, length: 6, style: "italic")])
        #expect(section.underlineStyles == [TextStyleRange(location: 10, length: 9, style: "underline")])
        #expect(section.strikethroughStyles == [TextStyleRange(location: 19, length: 6, style: "strikethrough")])
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
    func docxFormatterCapturesStyledRanges() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r>
              <w:r><w:rPr><w:i/></w:rPr><w:t>Italic</w:t></w:r>
              <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>Underline</w:t></w:r>
              <w:r><w:rPr><w:strike/></w:rPr><w:t>Strike</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>Lit</w:t></w:r>
              <w:r><w:rPr><w:shd w:val="clear" w:color="auto" w:fill="FFCC80"/></w:rPr><w:t>Shaded</w:t></w:r>
              <w:r><w:t>Plain</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let result = DocxFormatter().convertWithStyles(documentXML: xml)

        #expect(result.text == "BoldItalicUnderlineStrike\tLitShadedPlain\n")
        #expect(result.boldRanges == [TextStyleRange(location: 0, length: 4, style: "bold")])
        #expect(result.italicRanges == [TextStyleRange(location: 4, length: 6, style: "italic")])
        #expect(result.underlineRanges == [TextStyleRange(location: 10, length: 9, style: "underline")])
        #expect(result.strikethroughRanges == [TextStyleRange(location: 19, length: 6, style: "strikethrough")])
        #expect(result.highlightRanges.contains(TextStyleRange(location: 26, length: 3, style: "yellow")))
        #expect(result.highlightRanges.contains(TextStyleRange(location: 29, length: 6, style: "orange")))
    }

    @Test
    func sectionTextTransformParagraphSlicesPreserveRanges() {
        let text = "First\n\nSecond\n\n\nThird"
        let slices = SectionTextTransform.paragraphSlices(in: text)
        #expect(slices.count == 3)
        #expect(slices[0].text == "First\n\n")
        #expect(slices[1].text == "Second\n\n\n")
        #expect(slices[2].text == "Third")

        let nsText = text as NSString
        for slice in slices {
            #expect(nsText.substring(with: slice.range) == slice.text)
        }
    }

    @Test
    func sectionTextTransformClampSelectionRangeKeepsBounds() {
        let clamped = SectionTextTransform.clampSelectionRange(NSRange(location: -2, length: 10), textLength: 5)
        #expect(clamped.location == 0)
        #expect(clamped.length == 5)

        let empty = SectionTextTransform.clampSelectionRange(NSRange(location: 10, length: 2), textLength: 5)
        #expect(empty.location == 5)
        #expect(empty.length == 0)
    }

    @Test
    func sectionTextTransformStyledSectionClipsStyles() {
        let section = Section(
            id: UUID(),
            text: "Hello World",
            notes: ["Note"],
            resolvedNotes: ["Resolved"],
            colors: [TextStyleRange(location: 6, length: 5, style: "red")],
            highlights: [TextStyleRange(location: 0, length: 5, style: "yellow")]
        )

        let sliceRange = NSRange(location: 6, length: 5)
        let result = SectionTextTransform.styledSection(
            from: section,
            text: "World",
            sourceRange: sliceRange,
            id: UUID()
        )

        #expect(result.notes.isEmpty)
        #expect(result.resolvedNotes.isEmpty)
        #expect(result.colors == [TextStyleRange(location: 0, length: 5, style: "red")])
        #expect(result.highlights.isEmpty)
    }

    @Test
    func draftDiffEngineDiffHighlightsInsertionsAndDeletions() {
        let base = NSAttributedString(string: "Hello cruel world", attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let target = NSAttributedString(string: "Hello world", attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let diff = DraftDiffEngine.diffAttributedText(from: base, to: target)
        let nsDiff = NSAttributedString(diff)
        let range = (nsDiff.string as NSString).range(of: "cruel ")
        #expect(range.location != NSNotFound)
        let style = nsDiff.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)

        let insertedBase = NSAttributedString(string: "Hello world", attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let insertedTarget = NSAttributedString(string: "Hello brave world", attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let insertedDiff = DraftDiffEngine.diffAttributedText(from: insertedBase, to: insertedTarget)
        let insertedString = NSAttributedString(insertedDiff).string
        #expect(insertedString == "Hello brave world")
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
