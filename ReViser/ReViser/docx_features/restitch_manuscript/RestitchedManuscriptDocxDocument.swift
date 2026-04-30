import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct RestitchedManuscriptDocxDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "docx")!] }

    var sections: [Section]

    init(text: String = "") {
        self.sections = text.isEmpty ? [] : [Section(id: UUID(), text: text)]
    }

    init(sections: [Section]) {
        self.sections = sections
    }

    init(configuration: ReadConfiguration) throws {
        let text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        sections = text.isEmpty ? [] : [Section(id: UUID(), text: text)]
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("docx")

        try Self.writeDocxArchive(sections: sections, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try Data(contentsOf: tempURL)
        return FileWrapper(regularFileWithContents: data)
    }

    private static func writeDocxArchive(sections: [Section], to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let paragraphs = sections.isEmpty ? [Section(id: UUID(), text: "(Empty project)")] : sections

        let bodyXML = paragraphs.map { paragraph in
            let cleaned = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return "<w:p/>"
            }

            return styledParagraphXML(for: paragraph)
        }.joined(separator: "")

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" mc:Ignorable="w14 wp14">
          <w:body>
            \(bodyXML)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """

        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        try addArchiveEntry(archive, path: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        try addArchiveEntry(archive, path: "_rels/.rels", data: Data(relsXML.utf8))
        try addArchiveEntry(archive, path: "word/document.xml", data: Data(documentXML.utf8))
    }

    private static func styledParagraphXML(for section: Section) -> String {
        let text = section.text
        let nsText = text as NSString
        guard nsText.length > 0 else { return "<w:p/>" }

        var runs: [String] = []
        var currentText = ""
        var currentState = WordStyleState()

        func flushCurrentText() {
            guard !currentText.isEmpty else { return }
            runs.append(
                formatRun(
                    currentText,
                    state: currentState,
                    superscript: false,
                    subscript_: false
                )
            )
            currentText = ""
        }

        for index in 0..<nsText.length {
            let character = nsText.substring(with: NSRange(location: index, length: 1))

            if character == "\n" || character == "\r" {
                flushCurrentText()
                if character == "\r", index + 1 < nsText.length {
                    let nextCharacter = nsText.substring(with: NSRange(location: index + 1, length: 1))
                    if nextCharacter == "\n" {
                        continue
                    }
                }
                runs.append("<w:r><w:br/></w:r>")
                continue
            }

            let newState = WordStyleState(
                bold: sectionHasStyle(section.boldStyles, at: index),
                italic: sectionHasStyle(section.italicStyles, at: index),
                underline: sectionHasStyle(section.underlineStyles, at: index),
                strikethrough: sectionHasStyle(section.strikethroughStyles, at: index),
                color: sectionColorStyle(section.colors, at: index),
                highlight: sectionHighlightStyle(section.highlights, at: index),
                fontType: sectionFontTypeStyle(section.fontTypes, at: index),
                fontSize: sectionFontSizeStyle(section.fontSizes, at: index)
            )

            if currentText.isEmpty {
                currentState = newState
                currentText.append(character)
            } else if newState == currentState {
                currentText.append(character)
            } else {
                flushCurrentText()
                currentState = newState
                currentText.append(character)
            }
        }

        flushCurrentText()
        return "<w:p>\(runs.joined())</w:p>"
    }

    private static func sectionHasStyle(_ ranges: [TextStyleRange], at index: Int) -> Bool {
        ranges.contains { index >= $0.location && index < $0.location + $0.length }
    }

    private static func sectionColorStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextColorStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextColorStyle(rawValue: range.style)
    }

    private static func sectionHighlightStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextHighlightStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextHighlightStyle(rawValue: range.style)
    }

    private static func sectionFontTypeStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextFontTypeStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextFontTypeStyle(rawValue: range.style)
    }

    private static func sectionFontSizeStyle(_ ranges: [TextStyleRange], at index: Int) -> CGFloat? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style)
    }

    private struct WordStyleState: Equatable {
        let bold: Bool
        let italic: Bool
        let underline: Bool
        let strikethrough: Bool
        let color: ProjectDetailView.TextColorStyle?
        let highlight: ProjectDetailView.TextHighlightStyle?
        let fontType: ProjectDetailView.TextFontTypeStyle?
        let fontSize: CGFloat?

        init(
            bold: Bool = false,
            italic: Bool = false,
            underline: Bool = false,
            strikethrough: Bool = false,
            color: ProjectDetailView.TextColorStyle? = nil,
            highlight: ProjectDetailView.TextHighlightStyle? = nil,
            fontType: ProjectDetailView.TextFontTypeStyle? = nil,
            fontSize: CGFloat? = nil
        ) {
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
            self.color = color
            self.highlight = highlight
            self.fontType = fontType
            self.fontSize = fontSize
        }
    }

    private static func addArchiveEntry(_ archive: Archive, path: String, data: Data) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: position..<position + size)
        }
    }

    private static func formatRun(_ text: String, state: WordStyleState, superscript: Bool, subscript_: Bool) -> String {
        let escaped = xmlEscape(text)
        var xml = "<w:r>"

        if (state.bold || state.italic || state.underline || state.strikethrough || state.color != nil || state.highlight != nil || state.fontType != nil || state.fontSize != nil || superscript || subscript_
        ) {
            xml += "<w:rPr>"
            if let fontType = state.fontType {
                xml += "<w:rFonts w:ascii=\"\(fontType.docxFontName)\" w:hAnsi=\"\(fontType.docxFontName)\" w:cs=\"\(fontType.docxFontName)\"/>"
            }
            if state.bold {
                xml += "<w:b/>"
            }
            if state.italic {
                xml += "<w:i/>"
            }
            if state.strikethrough {
                xml += "<w:strike/>"
            }
            if let color = state.color {
                xml += "<w:color w:val=\"\(color.docxHexValue)\"/>"
            }
            if let fontSize = state.fontSize {
                let halfPoints = Int((fontSize * 2).rounded())
                xml += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
            }
            if let highlight = state.highlight {
                xml += "<w:highlight w:val=\"\(highlight.docxValue)\"/>"
            }
            if state.underline {
                xml += "<w:u w:val=\"single\"/>"
            }
            if let highlight = state.highlight {
                xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(highlight.docxShadingFillHex)\"/>"
            }
            if superscript {
                xml += "<w:vertAlign w:val=\"superscript\"/>"
            }
            if subscript_ {
                xml += "<w:vertAlign w:val=\"subscript\"/>"
            }
            xml += "</w:rPr>"
        }

        xml += "<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
        return xml
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
