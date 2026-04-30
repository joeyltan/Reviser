import SwiftUI
import UIKit

enum RestitchedManuscriptRenderer {
    static func attributedString(from sections: [Section]) -> AttributedString {
        let renderedSections = sections.isEmpty ? [Section(id: UUID(), text: "(Empty project)")] : sections
        let combined = NSMutableAttributedString()

        for (index, section) in renderedSections.enumerated() {
            let sectionAttributed = NSMutableAttributedString(string: section.text)
            let fullRange = NSRange(location: 0, length: (section.text as NSString).length)
            sectionAttributed.addAttributes([
                .font: UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ], range: fullRange)

            applyInlineStyles(
                to: sectionAttributed,
                text: section.text,
                colors: section.colors,
                highlights: section.highlights,
                fontTypes: section.fontTypes,
                fontSizes: section.fontSizes,
                boldStyles: section.boldStyles,
                italicStyles: section.italicStyles,
                underlineStyles: section.underlineStyles,
                strikethroughStyles: section.strikethroughStyles
            )

            combined.append(sectionAttributed)

            if index < renderedSections.count - 1 {
                combined.append(NSAttributedString(string: "\n"))
            }
        }

        if combined.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString("(Empty project)")
        }

        return AttributedString(combined)
    }

    private static func applyInlineStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        colors: [TextStyleRange],
        highlights: [TextStyleRange],
        fontTypes: [TextStyleRange],
        fontSizes: [TextStyleRange],
        boldStyles: [TextStyleRange],
        italicStyles: [TextStyleRange],
        underlineStyles: [TextStyleRange],
        strikethroughStyles: [TextStyleRange]
    ) {
        applyColorStyles(to: attributed, text: text, colors: colors)
        applyHighlightStyles(to: attributed, text: text, highlights: highlights)
        applyFontTypeStyles(to: attributed, text: text, fontTypes: fontTypes)
        applyFontSizeStyles(to: attributed, text: text, fontSizes: fontSizes)
        applyFontTraitStyles(to: attributed, text: text, ranges: boldStyles, trait: .traitBold)
        applyFontTraitStyles(to: attributed, text: text, ranges: italicStyles, trait: .traitItalic)

        let textLength = (text as NSString).length

        for range in underlineStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }

        for range in strikethroughStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private static func applyColorStyles(to attributed: NSMutableAttributedString, text: String, colors: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in colors {
            guard let style = ProjectDetailView.TextColorStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.foregroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private static func applyHighlightStyles(to attributed: NSMutableAttributedString, text: String, highlights: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in highlights {
            guard let style = ProjectDetailView.TextHighlightStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.backgroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private static func applyFontTypeStyles(to attributed: NSMutableAttributedString, text: String, fontTypes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontTypes {
            guard let style = ProjectDetailView.TextFontTypeStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            let font: UIFont
            if let design = style.uiKitDesign,
               let designedDescriptor = existingFont.fontDescriptor.withDesign(design) {
                font = UIFont(descriptor: designedDescriptor, size: existingFont.pointSize)
            } else {
                font = UIFont.systemFont(ofSize: existingFont.pointSize)
            }

            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private static func applyFontSizeStyles(to attributed: NSMutableAttributedString, text: String, fontSizes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontSizes {
            guard let pointSize = ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            attributed.addAttribute(.font, value: existingFont.withSize(pointSize), range: nsRange)
        }
    }

    private static func applyFontTraitStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        ranges: [TextStyleRange],
        trait: UIFontDescriptor.SymbolicTraits
    ) {
        let textLength = (text as NSString).length

        for range in ranges {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            let combinedTraits = existingFont.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(combinedTraits) {
                let font = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                attributed.addAttribute(.font, value: font, range: nsRange)
            }
        }
    }
}
