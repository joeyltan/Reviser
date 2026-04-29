import Foundation

struct DocxImportResult {
    var text: String
    var boldRanges: [TextStyleRange]
    var italicRanges: [TextStyleRange]
    var underlineRanges: [TextStyleRange]
    var strikethroughRanges: [TextStyleRange]
    var highlightRanges: [TextStyleRange]
}

class DocxFormatter: NSObject, XMLParserDelegate {
    private var resultText = ""
    private var resultLength = 0
    private var boldRanges: [TextStyleRange] = []
    private var italicRanges: [TextStyleRange] = []
    private var underlineRanges: [TextStyleRange] = []
    private var strikethroughRanges: [TextStyleRange] = []
    private var highlightRanges: [TextStyleRange] = []

    private var isBold = false
    private var isItalic = false
    private var isUnderline = false
    private var isStrikethrough = false
    private var currentHighlight: ProjectDetailView.TextHighlightStyle? = nil
    private var currentRunText = ""
    private var inText = false

    private var inParagraph = false
    private var isFirstRunInParagraph = false
    private var indentPrefix = ""
    private var listPrefix = ""

    func convertWithStyles(documentXML: String) -> DocxImportResult {
        resultText = ""
        resultLength = 0
        boldRanges = []
        italicRanges = []
        underlineRanges = []
        strikethroughRanges = []
        highlightRanges = []
        isBold = false
        isItalic = false
        isUnderline = false
        isStrikethrough = false
        currentHighlight = nil
        currentRunText = ""
        inText = false
        inParagraph = false
        isFirstRunInParagraph = false
        indentPrefix = ""
        listPrefix = ""

        let parser = XMLParser(data: documentXML.data(using: .utf8) ?? Data())
        parser.delegate = self
        parser.parse()

        return DocxImportResult(
            text: resultText,
            boldRanges: boldRanges,
            italicRanges: italicRanges,
            underlineRanges: underlineRanges,
            strikethroughRanges: strikethroughRanges,
            highlightRanges: highlightRanges
        )
    }

    func convert(documentXML: String) -> String {
        convertWithStyles(documentXML: documentXML).text
    }

    func parseWordprocessingML(_ xml: String) -> String {
        convert(documentXML: xml)
    }

    private func appendPlainText(_ text: String) {
        guard !text.isEmpty else { return }
        resultText += text
        resultLength += (text as NSString).length
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "w:tab":
            appendPlainText("\t")
        case "w:p":
            listPrefix = ""
            indentPrefix = ""
            inParagraph = true
            isFirstRunInParagraph = true
        case "w:r":
            isBold = false
            isItalic = false
            isUnderline = false
            isStrikethrough = false
            currentHighlight = nil
            currentRunText = ""
        case "w:b":
            if attributeDict["w:val"] != "0" && attributeDict["w:val"] != "false" {
                isBold = true
            }
        case "w:i":
            if attributeDict["w:val"] != "0" && attributeDict["w:val"] != "false" {
                isItalic = true
            }
        case "w:u":
            let val = attributeDict["w:val"] ?? "single"
            if val != "none" && val != "0" {
                isUnderline = true
            }
        case "w:strike":
            if attributeDict["w:val"] != "0" && attributeDict["w:val"] != "false" {
                isStrikethrough = true
            }
        case "w:highlight":
            if let val = attributeDict["w:val"], let style = Self.mapDocxHighlightValue(val) {
                currentHighlight = style
            }
        case "w:shd":
            if currentHighlight == nil,
               let fill = attributeDict["w:fill"],
               let style = Self.mapDocxShadingFill(fill) {
                currentHighlight = style
            }
        case "w:ind":
            if let firstLine = attributeDict["w:firstLine"], let value = Int(firstLine), value >= 720 {
                indentPrefix = "\t"
            } else if let left = attributeDict["w:left"], let value = Int(left), value >= 720 {
                indentPrefix = "\t"
            }
        case "w:numPr":
            listPrefix = "- "
        case "w:t":
            inText = true
            currentRunText = ""
        case "w:br":
            appendPlainText("\n")
        case "w:pageBreakBefore":
            appendPlainText("\n")
        case "w:lastRenderedPageBreak":
            appendPlainText("\n\n")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:p":
            if inParagraph {
                appendPlainText("\n")
                inParagraph = false
            }
        case "w:r":
            if isFirstRunInParagraph {
                appendPlainText(listPrefix + indentPrefix)
                isFirstRunInParagraph = false
            }
            let runStart = resultLength
            appendPlainText(currentRunText)
            let runLength = resultLength - runStart
            if runLength > 0 {
                if isBold {
                    boldRanges.append(TextStyleRange(location: runStart, length: runLength, style: ProjectDetailView.TextStyle.bold.rawValue))
                }
                if isItalic {
                    italicRanges.append(TextStyleRange(location: runStart, length: runLength, style: ProjectDetailView.TextStyle.italic.rawValue))
                }
                if isUnderline {
                    underlineRanges.append(TextStyleRange(location: runStart, length: runLength, style: ProjectDetailView.TextStyle.underline.rawValue))
                }
                if isStrikethrough {
                    strikethroughRanges.append(TextStyleRange(location: runStart, length: runLength, style: ProjectDetailView.TextStyle.strikethrough.rawValue))
                }
                if let highlight = currentHighlight {
                    highlightRanges.append(TextStyleRange(location: runStart, length: runLength, style: highlight.rawValue))
                }
            }
        case "w:t":
            inText = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            currentRunText += string
        }
    }

    private static func mapDocxHighlightValue(_ value: String) -> ProjectDetailView.TextHighlightStyle? {
        switch value {
        case "yellow": return .yellow
        case "darkYellow": return .orange
        case "green": return .green
        case "magenta": return .pink
        case "blue": return .blue
        default: return nil
        }
    }

    private static func mapDocxShadingFill(_ hex: String) -> ProjectDetailView.TextHighlightStyle? {
        switch hex.uppercased() {
        case "FFF59D": return .yellow
        case "FFCC80": return .orange
        case "C5E1A5": return .green
        case "F8BBD0": return .pink
        case "B3E5FC": return .blue
        default: return nil
        }
    }
}
