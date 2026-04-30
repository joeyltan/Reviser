import Foundation

enum SectionTextTransform {
    static func clampSelectionRange(_ range: NSRange, textLength: Int) -> NSRange {
        let clampedLocation = min(max(range.location, 0), textLength)
        let clampedLength = min(max(range.length, 0), textLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    static func offsetRanges(_ ranges: [TextStyleRange], by delta: Int) -> [TextStyleRange] {
        guard delta != 0 else { return ranges }
        return ranges.map { TextStyleRange(location: $0.location + delta, length: $0.length, style: $0.style) }
    }

    static func clippedRanges(_ ranges: [TextStyleRange], in sourceRange: NSRange) -> [TextStyleRange] {
        let sourceStart = sourceRange.location
        let sourceEnd = sourceRange.location + sourceRange.length

        return ranges.compactMap { range in
            let rangeStart = range.location
            let rangeEnd = range.location + range.length
            let clippedStart = max(rangeStart, sourceStart)
            let clippedEnd = min(rangeEnd, sourceEnd)

            guard clippedEnd > clippedStart else { return nil }

            return TextStyleRange(
                location: clippedStart - sourceStart,
                length: clippedEnd - clippedStart,
                style: range.style
            )
        }
    }

    static func styledSection(from section: Section, text: String, sourceRange: NSRange, id: UUID) -> Section {
        Section(
            id: id,
            text: text,
            notes: sourceRange.location == 0 ? section.notes : [],
            resolvedNotes: sourceRange.location == 0 ? section.resolvedNotes : [],
            colors: clippedRanges(section.colors, in: sourceRange),
            highlights: clippedRanges(section.highlights, in: sourceRange),
            fontTypes: clippedRanges(section.fontTypes, in: sourceRange),
            fontSizes: clippedRanges(section.fontSizes, in: sourceRange),
            boldStyles: clippedRanges(section.boldStyles, in: sourceRange),
            italicStyles: clippedRanges(section.italicStyles, in: sourceRange),
            underlineStyles: clippedRanges(section.underlineStyles, in: sourceRange),
            strikethroughStyles: clippedRanges(section.strikethroughStyles, in: sourceRange)
        )
    }

    static func paragraphSlices(in text: String) -> [(text: String, range: NSRange)] {
        let nsText = text as NSString
        var slices: [(text: String, range: NSRange)] = []
        var currentParagraph = ""
        var separatorRun = ""
        var separatorStart: Int?
        var paragraphStart: Int?
        var hasParagraphContent = false
        var index = 0

        while index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let lineText = nsText.substring(with: lineRange)
            let isBlank = lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isBlank {
                if !hasParagraphContent && separatorStart == nil {
                    separatorStart = lineRange.location
                }
                separatorRun += lineText
            } else {
                if !hasParagraphContent {
                    paragraphStart = separatorStart ?? lineRange.location
                    currentParagraph = separatorRun + lineText
                    separatorRun = ""
                    separatorStart = nil
                    hasParagraphContent = true
                } else if !separatorRun.isEmpty {
                    if let start = paragraphStart {
                        let length = (currentParagraph as NSString).length + (separatorRun as NSString).length
                        slices.append((currentParagraph + separatorRun, NSRange(location: start, length: length)))
                    }
                    paragraphStart = lineRange.location
                    currentParagraph = lineText
                    separatorRun = ""
                    separatorStart = nil
                } else {
                    currentParagraph += lineText
                }
            }

            index = lineRange.location + lineRange.length
        }

        if hasParagraphContent {
            if let start = paragraphStart {
                let length = (currentParagraph as NSString).length + (separatorRun as NSString).length
                slices.append((currentParagraph + separatorRun, NSRange(location: start, length: length)))
            }
        } else if !separatorRun.isEmpty {
            let start = separatorStart ?? 0
            slices.append((separatorRun, NSRange(location: start, length: (separatorRun as NSString).length)))
        }

        return slices
    }
}
