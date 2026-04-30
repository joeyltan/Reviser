import Foundation
import UIKit

struct DraftDiffEngine {
    enum Operation {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    static func diffAttributedText(from baseAttr: NSAttributedString, to targetAttr: NSAttributedString) -> AttributedString {
        let baseText = baseAttr.string
        let targetText = targetAttr.string
        let baseChunks = sentenceChunks(in: baseText)
        let targetChunks = sentenceChunks(in: targetText)
        let operations = diffOperations(from: baseChunks, to: targetChunks)
        let result = NSMutableAttributedString()
        var baseIdx = 0
        var targetIdx = 0
        var index = 0

        while index < operations.count {
            switch operations[index] {
            case .equal(let token):
                let len = (token as NSString).length
                if len > 0 {
                    result.append(targetAttr.attributedSubstring(from: NSRange(location: targetIdx, length: len)))
                }
                baseIdx += len
                targetIdx += len
                index += 1
            case .delete(let baseChunk):
                let baseLen = (baseChunk as NSString).length
                if index + 1 < operations.count,
                   case .insert(let targetChunk) = operations[index + 1],
                   sentencesAreSimilar(baseChunk, targetChunk) {
                    let targetLen = (targetChunk as NSString).length
                    appendWordLevelDiff(
                        from: baseAttr,
                        baseRange: NSRange(location: baseIdx, length: baseLen),
                        to: targetAttr,
                        targetRange: NSRange(location: targetIdx, length: targetLen),
                        into: result
                    )
                    baseIdx += baseLen
                    targetIdx += targetLen
                    index += 2
                } else {
                    if baseLen > 0 {
                        let sub = NSMutableAttributedString(attributedString: baseAttr.attributedSubstring(from: NSRange(location: baseIdx, length: baseLen)))
                        applyDiffOverlay(
                            to: sub,
                            foregroundColor: UIColor.systemRed,
                            backgroundColor: UIColor.systemRed.withAlphaComponent(0.18),
                            strikethrough: true
                        )
                        result.append(sub)
                    }
                    baseIdx += baseLen
                    index += 1
                }
            case .insert(let token):
                let len = (token as NSString).length
                if len > 0 {
                    let sub = NSMutableAttributedString(attributedString: targetAttr.attributedSubstring(from: NSRange(location: targetIdx, length: len)))
                    applyDiffOverlay(
                        to: sub,
                        foregroundColor: UIColor.systemGreen,
                        backgroundColor: UIColor.systemGreen.withAlphaComponent(0.24)
                    )
                    result.append(sub)
                }
                targetIdx += len
                index += 1
            }
        }

        return AttributedString(result)
    }

    static func sentencesAreSimilar(_ a: String, _ b: String) -> Bool {
        let aTokens = contentWordTokens(in: a)
        let bTokens = contentWordTokens(in: b)
        guard !aTokens.isEmpty, !bTokens.isEmpty else { return false }

        let diff = bTokens.difference(from: aTokens)
        let lcsLength = aTokens.count - diff.removals.count
        let denominator = max(aTokens.count, bTokens.count)
        guard denominator > 0 else { return false }
        return Double(lcsLength) / Double(denominator) >= 0.4
    }

    static func contentWordTokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func appendWordLevelDiff(
        from baseAttr: NSAttributedString,
        baseRange: NSRange,
        to targetAttr: NSAttributedString,
        targetRange: NSRange,
        into result: NSMutableAttributedString
    ) {
        let baseSubText = baseAttr.attributedSubstring(from: baseRange).string
        let targetSubText = targetAttr.attributedSubstring(from: targetRange).string
        let baseTokens = wordTokens(in: baseSubText)
        let targetTokens = wordTokens(in: targetSubText)
        let operations = diffOperations(from: baseTokens, to: targetTokens)

        var baseLocalIdx = 0
        var targetLocalIdx = 0

        for operation in operations {
            switch operation {
            case .equal(let token):
                let len = (token as NSString).length
                if len > 0 {
                    let absRange = NSRange(location: targetRange.location + targetLocalIdx, length: len)
                    result.append(targetAttr.attributedSubstring(from: absRange))
                }
                baseLocalIdx += len
                targetLocalIdx += len
            case .insert(let token):
                let len = (token as NSString).length
                if len > 0 {
                    let absRange = NSRange(location: targetRange.location + targetLocalIdx, length: len)
                    let sub = NSMutableAttributedString(attributedString: targetAttr.attributedSubstring(from: absRange))
                    applyDiffOverlay(
                        to: sub,
                        foregroundColor: UIColor.systemGreen,
                        backgroundColor: UIColor.systemGreen.withAlphaComponent(0.24)
                    )
                    result.append(sub)
                }
                targetLocalIdx += len
            case .delete(let token):
                let len = (token as NSString).length
                if len > 0 {
                    let absRange = NSRange(location: baseRange.location + baseLocalIdx, length: len)
                    let sub = NSMutableAttributedString(attributedString: baseAttr.attributedSubstring(from: absRange))
                    applyDiffOverlay(
                        to: sub,
                        foregroundColor: UIColor.systemRed,
                        backgroundColor: UIColor.systemRed.withAlphaComponent(0.18),
                        strikethrough: true
                    )
                    result.append(sub)
                }
                baseLocalIdx += len
            }
        }
    }

    static func applyDiffOverlay(
        to attr: NSMutableAttributedString,
        foregroundColor: UIColor? = nil,
        backgroundColor: UIColor? = nil,
        strikethrough: Bool = false
    ) {
        let range = NSRange(location: 0, length: attr.length)
        guard range.length > 0 else { return }
        if let foregroundColor {
            attr.addAttribute(.foregroundColor, value: foregroundColor, range: range)
        }
        if let backgroundColor {
            attr.addAttribute(.backgroundColor, value: backgroundColor, range: range)
        }
        if strikethrough {
            attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    static func wordTokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var tokens: [String] = []
        var startIndex = text.startIndex
        var isWhitespace = text[startIndex].isWhitespace
        var index = text.index(after: startIndex)

        while index < text.endIndex {
            let currentIsWhitespace = text[index].isWhitespace
            if currentIsWhitespace != isWhitespace {
                tokens.append(String(text[startIndex..<index]))
                startIndex = index
                isWhitespace = currentIsWhitespace
            }
            index = text.index(after: index)
        }

        tokens.append(String(text[startIndex..<text.endIndex]))
        return tokens
    }

    static func sentenceChunks(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        var chunks: [String] = []
        var cursor = text.startIndex
        var foundSentence = false

        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .bySentences) { _, sentenceRange, _, _ in
            guard sentenceRange.location != NSNotFound else { return }

            foundSentence = true
            let start = text.index(text.startIndex, offsetBy: sentenceRange.location)
            let end = text.index(text.startIndex, offsetBy: sentenceRange.location + sentenceRange.length)

            if cursor < end {
                chunks.append(String(text[cursor..<end]))
                cursor = end
            }
        }

        if foundSentence, cursor < text.endIndex {
            chunks.append(String(text[cursor..<text.endIndex]))
        }

        if !foundSentence {
            return [text]
        }

        return chunks.isEmpty ? [text] : chunks
    }

    static func diffOperations(from baseTokens: [String], to targetTokens: [String]) -> [Operation] {
        let difference = targetTokens.difference(from: baseTokens)
        let removals: [CollectionDifference<String>.Change] = difference.removals
        let insertions: [CollectionDifference<String>.Change] = difference.insertions

        var operations: [Operation] = []
        var baseIndex = 0
        var targetIndex = 0
        var removalIndex = 0
        var insertionIndex = 0

        let sortedRemovals = removals.sorted(by: { changeOffset($0) < changeOffset($1) })
        let sortedInsertions = insertions.sorted(by: { changeOffset($0) < changeOffset($1) })

        while baseIndex < baseTokens.count || targetIndex < targetTokens.count {
            while removalIndex < sortedRemovals.count, changeOffset(sortedRemovals[removalIndex]) == baseIndex {
                operations.append(.delete(baseTokens[baseIndex]))
                baseIndex += 1
                removalIndex += 1
            }

            while insertionIndex < sortedInsertions.count, changeOffset(sortedInsertions[insertionIndex]) == targetIndex {
                operations.append(.insert(targetTokens[targetIndex]))
                targetIndex += 1
                insertionIndex += 1
            }

            if baseIndex < baseTokens.count,
               targetIndex < targetTokens.count,
               baseTokens[baseIndex] == targetTokens[targetIndex] {
                operations.append(.equal(baseTokens[baseIndex]))
                baseIndex += 1
                targetIndex += 1
                continue
            }

            if baseIndex < baseTokens.count {
                operations.append(.delete(baseTokens[baseIndex]))
                baseIndex += 1
                continue
            }

            if targetIndex < targetTokens.count {
                operations.append(.insert(targetTokens[targetIndex]))
                targetIndex += 1
                continue
            }
        }

        return operations
    }

    static func changeOffset(_ change: CollectionDifference<String>.Change) -> Int {
        switch change {
        case .insert(let offset, _, _):
            return offset
        case .remove(let offset, _, _):
            return offset
        }
    }
}
