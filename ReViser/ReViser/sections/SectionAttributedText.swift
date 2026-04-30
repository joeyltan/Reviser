import SwiftUI
import UIKit

enum SectionAttributedText {
    static func attributedString(for section: Section, limit: Int? = nil, baseFontSize: CGFloat = 25) -> AttributedString {
        let nsText = section.text as NSString
        let textLength = limit.map { min($0, nsText.length) } ?? nsText.length

        if textLength == 0 {
            return AttributedString("(Empty section)")
        }

        let displayText = nsText.substring(with: NSRange(location: 0, length: textLength))
        let attributed = NSMutableAttributedString(string: displayText)
        let fullRange = NSRange(location: 0, length: textLength)

        attributed.addAttributes([
            .font: UIFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: UIColor.label
        ], range: fullRange)

        applyColorStyles(to: attributed, text: displayText, colors: clippedRanges(section.colors, limit: textLength))
        applyHighlightStyles(to: attributed, text: displayText, highlights: clippedRanges(section.highlights, limit: textLength))
        applyFontTypeStyles(to: attributed, text: displayText, fontTypes: clippedRanges(section.fontTypes, limit: textLength), baseFontSize: baseFontSize)
        applyFontSizeStyles(to: attributed, text: displayText, fontSizes: clippedRanges(section.fontSizes, limit: textLength), baseFontSize: baseFontSize)
        applyFontTraitStyles(to: attributed, text: displayText, ranges: clippedRanges(section.boldStyles, limit: textLength), trait: .traitBold, baseFontSize: baseFontSize)
        applyFontTraitStyles(to: attributed, text: displayText, ranges: clippedRanges(section.italicStyles, limit: textLength), trait: .traitItalic, baseFontSize: baseFontSize)
        applyUnderlineStyles(to: attributed, text: displayText, underlineStyles: clippedRanges(section.underlineStyles, limit: textLength))
        applyStrikethroughStyles(to: attributed, text: displayText, strikethroughStyles: clippedRanges(section.strikethroughStyles, limit: textLength))

        return AttributedString(attributed)
    }

    private static func clippedRanges(_ ranges: [TextStyleRange], limit: Int) -> [TextStyleRange] {
        let clippingRange = NSRange(location: 0, length: limit)

        return ranges.compactMap { range in
            let intersection = NSIntersectionRange(range.nsRange, clippingRange)
            guard intersection.length > 0 else { return nil }
            return TextStyleRange(location: intersection.location, length: intersection.length, style: range.style)
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

    private static func applyFontTypeStyles(to attributed: NSMutableAttributedString, text: String, fontTypes: [TextStyleRange], baseFontSize: CGFloat) {
        let textLength = (text as NSString).length

        for range in fontTypes {
            guard let style = ProjectDetailView.TextFontTypeStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: baseFontSize)
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

    private static func applyFontSizeStyles(to attributed: NSMutableAttributedString, text: String, fontSizes: [TextStyleRange], baseFontSize: CGFloat) {
        let textLength = (text as NSString).length

        for range in fontSizes {
            guard let pointSize = ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: baseFontSize)
            attributed.addAttribute(.font, value: existingFont.withSize(pointSize), range: nsRange)
        }
    }

    private static func applyFontTraitStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        ranges: [TextStyleRange],
        trait: UIFontDescriptor.SymbolicTraits,
        baseFontSize: CGFloat
    ) {
        let textLength = (text as NSString).length

        for range in ranges {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: baseFontSize)
            let combinedTraits = existingFont.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(combinedTraits) {
                let font = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                attributed.addAttribute(.font, value: font, range: nsRange)
            }
        }
    }

    private static func applyUnderlineStyles(to attributed: NSMutableAttributedString, text: String, underlineStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in underlineStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private static func applyStrikethroughStyles(to attributed: NSMutableAttributedString, text: String, strikethroughStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in strikethroughStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }
}