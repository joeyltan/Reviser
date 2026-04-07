import Foundation

class DocxFormatter: NSObject, XMLParserDelegate {
    private var result = ""
    private var currentText = ""
    private var isBold = false
    private var isItalic = false
    private var isUnderline = false
    private var isStrikethrough = false
    private var inText = false
    private var inParagraph = false
    private var paragraphPrefix = ""
    private var isFirstRunInParagraph = false
    private var indentPrefix = ""
    private var listPrefix = ""
    
    func convert(documentXML: String) -> String {
        result = ""
        currentText = ""
        isBold = false
        isItalic = false
        isUnderline = false
        isStrikethrough = false
        inText = false
        inParagraph = false
        paragraphPrefix = ""
        isFirstRunInParagraph = false
        indentPrefix = ""
        listPrefix = ""
        
        let parser = XMLParser(data: documentXML.data(using: .utf8) ?? Data())
        parser.delegate = self
        parser.parse()
        
        return result
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "w:tab":
            result += "\t"
        case "w:p":
            paragraphPrefix = ""
            listPrefix = ""
            indentPrefix = ""
            inParagraph = true
            isFirstRunInParagraph = true
        case "w:r":
            // Reset formatting for each run
            isBold = false
            isItalic = false
            isUnderline = false
            isStrikethrough = false
            currentText = ""
        case "w:b":
            isBold = true
        case "w:i":
            isItalic = true
        case "w:u":
            isUnderline = true
        case "w:strike":
            isStrikethrough = true
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
            currentText = ""
        case "w:br": // line break
            result += "\n"
        case "w:pageBreakBefore": // page break
            result += "\n"
        case "w:lastRenderedPageBreak": 
            result += "\n\n"
        default:
            break
        }
        // come back and make sure all formatting has been addressed
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:p":
            if inParagraph {
                result += "\n"
                inParagraph = false
                paragraphPrefix = ""
            }
        case "w:r":
            // Apply formatting to currentText and append
            if isFirstRunInParagraph {
                paragraphPrefix = listPrefix + indentPrefix
                result += paragraphPrefix
                isFirstRunInParagraph = false
            }
            var formattedText = currentText
            if isBold {
                formattedText = "**\(formattedText)**"
            }
            if isItalic {
                formattedText = "_\(formattedText)_"
            }
            if isUnderline {
                formattedText = "__\(formattedText)__"
            }
            if isStrikethrough {
                formattedText = "~~\(formattedText)~~"
            }
            result += formattedText
        case "w:t":
            inText = false
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }
    
    // Legacy method for backward compatibility
    func parseWordprocessingML(_ xml: String) -> String {
        return convert(documentXML: xml)
    }
}
