import SwiftUI
import UIKit

struct TextKitView: UIViewRepresentable {
    struct RenderState: Equatable {
        var text: String
        var highlightedSnippets: Set<String>
        var textColors: [TextStyleRange]
        var textHighlights: [TextStyleRange]
        var textFontTypes: [TextStyleRange]
        var textFontSizes: [TextStyleRange]
        var textBoldStyles: [TextStyleRange]
        var textItalicStyles: [TextStyleRange]
        var textUnderlineStyles: [TextStyleRange]
        var textStrikethroughStyles: [TextStyleRange]
    }

    @Binding var text: String
    var highlightedSnippets: Set<String> = []
    var textColors: [TextStyleRange] = []
    var textHighlights: [TextStyleRange] = []
    var textFontTypes: [TextStyleRange] = []
    var textFontSizes: [TextStyleRange] = []
    var textBoldStyles: [TextStyleRange] = []
    var textItalicStyles: [TextStyleRange] = []
    var textUnderlineStyles: [TextStyleRange] = []
    var textStrikethroughStyles: [TextStyleRange] = []
    var onAttach: (UITextView) -> Void
    var onSelectionChange: (Int, Int) -> Void
    @Binding var calculatedHeight: CGFloat
    var onHighlightedSnippetAnchorsChange: (([String: [CGPoint]]) -> Void)? = nil
    var selectionMenuBuilder: (([UIMenuElement]) -> UIMenu?)? = nil

    private var renderState: RenderState {
        RenderState(
            text: text,
            highlightedSnippets: highlightedSnippets,
            textColors: textColors,
            textHighlights: textHighlights,
            textFontTypes: textFontTypes,
            textFontSizes: textFontSizes,
            textBoldStyles: textBoldStyles,
            textItalicStyles: textItalicStyles,
            textUnderlineStyles: textUnderlineStyles,
            textStrikethroughStyles: textStrikethroughStyles
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()

        view.font = UIFont.systemFont(ofSize: 25)
        view.isScrollEnabled = true
        view.backgroundColor = .clear
        view.delegate = context.coordinator

        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byWordWrapping

        view.isEditable = true
        view.isSelectable = true

        context.coordinator.textView = view
        DispatchQueue.main.async {
            self.onAttach(view)
            self.onSelectionChange(view.selectedRange.location, view.selectedRange.length)
        }

        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let currentRenderState = renderState
        let didChangeRenderedContent = coordinator.lastRenderState != currentRenderState
        let didChangeWidth = coordinator.lastMeasuredWidth != uiView.bounds.width

        if didChangeRenderedContent {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = makeAttributedText(from: text)

            let clampedLocation = min(selectedRange.location, uiView.attributedText.length)
            let maxLength = max(0, uiView.attributedText.length - clampedLocation)
            let clampedLength = min(selectedRange.length, maxLength)
            uiView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
            coordinator.lastRenderState = currentRenderState
        }

        guard didChangeRenderedContent || didChangeWidth else { return }

        DispatchQueue.main.async {
            let newHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)).height
            if self.calculatedHeight != newHeight {
                self.calculatedHeight = newHeight
            }

            if didChangeRenderedContent || didChangeWidth {
                self.onHighlightedSnippetAnchorsChange?(self.computeSnippetAnchorPoints(in: uiView))
            }
            coordinator.lastMeasuredWidth = uiView.bounds.width
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func makeAttributedText(from text: String) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([
            .font: UIFont.systemFont(ofSize: 25),
            .foregroundColor: UIColor.label
        ], range: fullRange)

        applyFontTypeStyles(to: attributed, text: text, fontTypes: textFontTypes)
        applyFontSizeStyles(to: attributed, text: text, fontSizes: textFontSizes)
        applyBoldStyles(to: attributed, text: text, boldStyles: textBoldStyles)
        applyItalicStyles(to: attributed, text: text, italicStyles: textItalicStyles)
        applyUnderlineStyles(to: attributed, text: text, underlineStyles: textUnderlineStyles)
        applyStrikethroughStyles(to: attributed, text: text, strikethroughStyles: textStrikethroughStyles)
        applyColorStyles(to: attributed, text: text, colors: textColors)
        applyHighlightStyles(to: attributed, text: text, highlights: textHighlights)

        for snippet in highlightedSnippets where !snippet.isEmpty {
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)

            while true {
                let found = nsText.range(of: snippet, options: [], range: searchRange)
                if found.location == NSNotFound { break }

                attributed.addAttribute(
                    .backgroundColor,
                    value: UIColor.systemOrange.withAlphaComponent(0.30),
                    range: found
                )

                let nextStart = found.location + found.length
                if nextStart >= nsText.length { break }
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            }
        }

        return attributed
    }

    private func applyHighlightStyles(to attributed: NSMutableAttributedString, text: String, highlights: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in highlights {
            guard let style = ProjectDetailView.TextHighlightStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.backgroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyColorStyles(to attributed: NSMutableAttributedString, text: String, colors: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in colors {
            guard let style = ProjectDetailView.TextColorStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.foregroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyFontTypeStyles(to attributed: NSMutableAttributedString, text: String, fontTypes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontTypes {
            guard let style = ProjectDetailView.TextFontTypeStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let font: UIFont
            if let design = style.uiKitDesign, let designedFont = existingFont.fontDescriptor.withDesign(design).flatMap({ UIFont(descriptor: $0, size: existingFont.pointSize) }) {
                font = designedFont
            } else {
                font = UIFont.systemFont(ofSize: existingFont.pointSize)
            }

            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private func applyFontSizeStyles(to attributed: NSMutableAttributedString, text: String, fontSizes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontSizes {
            guard let pointSize = ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let font = existingFont.withSize(pointSize)
            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private func applyBoldStyles(to attributed: NSMutableAttributedString, text: String, boldStyles: [TextStyleRange]) {
        applyFontTraitStyles(to: attributed, text: text, ranges: boldStyles, trait: .traitBold)
    }

    private func applyItalicStyles(to attributed: NSMutableAttributedString, text: String, italicStyles: [TextStyleRange]) {
        applyFontTraitStyles(to: attributed, text: text, ranges: italicStyles, trait: .traitItalic)
    }

    private func applyUnderlineStyles(to attributed: NSMutableAttributedString, text: String, underlineStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in underlineStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyStrikethroughStyles(to attributed: NSMutableAttributedString, text: String, strikethroughStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in strikethroughStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyFontTraitStyles(to attributed: NSMutableAttributedString, text: String, ranges: [TextStyleRange], trait: UIFontDescriptor.SymbolicTraits) {
        let textLength = (text as NSString).length

        for range in ranges {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let combinedTraits = existingFont.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(combinedTraits) {
                let font = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                attributed.addAttribute(.font, value: font, range: nsRange)
            }
        }
    }

    private func computeSnippetAnchorPoints(in textView: UITextView) -> [String: [CGPoint]] {
        guard !highlightedSnippets.isEmpty else { return [:] }

        var result: [String: [CGPoint]] = [:]
        let text = textView.text ?? ""
        let nsText = text as NSString
        let layoutManager = textView.layoutManager

        for snippet in highlightedSnippets where !snippet.isEmpty {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while true {
                let found = nsText.range(of: snippet, options: [], range: searchRange)
                if found.location == NSNotFound { break }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: found, actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)

                rect.origin.x += textView.textContainerInset.left
                rect.origin.y += textView.textContainerInset.top - textView.contentOffset.y

                let anchor = CGPoint(x: rect.minX, y: rect.minY)
                result[snippet, default: []].append(anchor)

                let nextStart = found.location + found.length
                if nextStart >= nsText.length { break }
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            }
        }

        return result
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextKitView
        var textView: UITextView?
        var lastRenderState: RenderState?
        var lastMeasuredWidth: CGFloat?

        init(_ parent: TextKitView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onSelectionChange(textView.selectedRange.location, textView.selectedRange.length)
        }

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn textRange: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            parent.selectionMenuBuilder?(suggestedActions)
        }
    }
}
