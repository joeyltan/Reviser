import SwiftUI
import UniformTypeIdentifiers
import RadixUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var isLoading = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        ZStack {
            VStack(spacing: 24) {
                HStack(alignment: .center) {
                    VStack(spacing: 8) {
                        Text("ReViser")
                            .font(.largeTitle)
                            .bold()
                        Text("A spatial visualization editing application")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import Document", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            openWindow(id: "compare-window")
                        } label: {
                            Label("Compare Drafts", systemImage: "rectangle.split.2x1")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 1100)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.top, 14)

                VStack(spacing: 10) {
                    // Search field for project titles
                    TextField("Search projects", text: $model.searchQuery)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 1100)

                // Projects list
                if model.filteredProjects.isEmpty {
                    ContentUnavailableView("No Projects", systemImage: "doc.on.doc", description: Text("Import a document to create a project."))
                        .frame(maxWidth: .infinity)
                } else {
                    let projectColumns = [
                        GridItem(.flexible(minimum: 280), spacing: 16),
                        GridItem(.flexible(minimum: 280), spacing: 16)
                    ]

                    ScrollView {
                        LazyVGrid(columns: projectColumns, alignment: .leading, spacing: 16) {
                            ForEach(model.filteredProjects) { project in
                                NavigationLink(destination: ProjectDetailView(projectID: project.id)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(project.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(model.previewText(for: project))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(4)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(.thinMaterial)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(.quaternary, lineWidth: 1)
                                    )
                                    .shadow(radius: 6, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 0)
            }
            .padding(32)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: model.supportedContentTypes) { result in
            switch result {
            case .success(let url):
                Task { @MainActor in
                    isLoading = true
                }
                Task {
                    await model.loadDocument(from: url)
//                    print("after load", model.projects.first?.title)
// this is empty what
                    // print("after load 2", model.projects.first?.text)
                    await MainActor.run { isLoading = false }
                }
            case .failure:
                break
            }
        }
    }
    
}

enum DraftComparisonMode: String, CaseIterable, Identifiable {
    case sectioned
    case unsectioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sectioned: return "Sectioned"
        case .unsectioned: return "Unsectioned"
        }
    }
}

struct DraftCompareSlot: Identifiable, Equatable {
    let id: UUID = UUID()
    var projectID: UUID? = nil
    var mode: DraftComparisonMode = .sectioned
}

extension VerticalAlignment {
    private struct DraftDocumentTopID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.top]
        }
    }
    static let draftDocumentTop = VerticalAlignment(DraftDocumentTopID.self)
}

struct CompareDraftsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draftSlots: [DraftCompareSlot] = [
        DraftCompareSlot(mode: .sectioned),
        DraftCompareSlot(mode: .unsectioned)
    ]
    @State private var showDraftDiff: Bool = true

    private let columnSpacing: CGFloat = 24
    private let outerPadding: CGFloat = 24
    private let minColumnWidth: CGFloat = 360

    var body: some View {
        NavigationStack {
            Group {
                if model.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "doc.on.doc",
                        description: Text("Import projects to compare drafts.")
                    )
                } else {
                    GeometryReader { proxy in
                        let columnCount = max(draftSlots.count, 1)
                        let availableWidth = max(proxy.size.width - outerPadding * 2, minColumnWidth)
                        let widthPerColumn = (availableWidth - CGFloat(columnCount - 1) * columnSpacing - 80) / CGFloat(columnCount)
                        let sideWidth = max(minColumnWidth, widthPerColumn)
                        let baselineSlot = draftSlots.first

                        ScrollView(.horizontal) {
                            HStack(alignment: .draftDocumentTop, spacing: columnSpacing) {
                                ForEach(Array(draftSlots.enumerated()), id: \.element.id) { index, _ in
                                    let slotBinding = Binding<DraftCompareSlot>(
                                        get: { draftSlots[index] },
                                        set: { draftSlots[index] = $0 }
                                    )
                                    let isBaseline = index == 0
                                    compareColumn(
                                        title: isBaseline ? "Baseline Draft" : "Draft \(index)",
                                        slot: slotBinding,
                                        width: sideWidth,
                                        isBaseline: isBaseline,
                                        comparedAgainstSlot: isBaseline ? nil : baselineSlot,
                                        onRemove: draftSlots.count > 2 ? {
                                            removeSlot(at: index)
                                        } : nil
                                    )
                                }

                                addDraftButton
                            }
                            .padding(outerPadding)
                        }
                        .scrollIndicators(.visible)
                    }
                }
            }
            .navigationTitle("Compare Drafts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDraftDiff.toggle()
                    } label: {
                        Label(showDraftDiff ? "Hide Diff" : "Show Diff", systemImage: showDraftDiff ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .help(showDraftDiff ? "Hide draft differences" : "Show draft differences")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            initializeSelectionIfNeeded()
        }
        .task(id: model.projects.map { $0.id }) {
            initializeSelectionIfNeeded()
        }
    }

    private func initializeSelectionIfNeeded() {
        guard !model.projects.isEmpty else { return }

        for index in draftSlots.indices where draftSlots[index].projectID == nil {
            let fallbackIndex = min(index, model.projects.count - 1)
            draftSlots[index].projectID = model.projects[fallbackIndex].id
        }
    }

    private func addDraftSlot() {
        let nextProject = model.projects.first { project in
            !draftSlots.contains(where: { $0.projectID == project.id })
        } ?? model.projects.first
        draftSlots.append(DraftCompareSlot(projectID: nextProject?.id, mode: .sectioned))
    }

    private func removeSlot(at index: Int) {
        guard draftSlots.indices.contains(index), draftSlots.count > 2 else { return }
        draftSlots.remove(at: index)
    }

    @ViewBuilder
    private var addDraftButton: some View {
        Button {
            addDraftSlot()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                Text("Add Draft")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160)
            .frame(minHeight: 500)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
        .help("Add another draft column to the comparison")
        .padding(5)
        .alignmentGuide(.draftDocumentTop) { d in d[.top] }
    }

    @ViewBuilder
    private func compareColumn(
        title: String,
        slot: Binding<DraftCompareSlot>,
        width: CGFloat,
        isBaseline: Bool,
        comparedAgainstSlot: DraftCompareSlot?,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        let projectID = slot.wrappedValue.projectID
        let mode = slot.mode

        let selectedProject = projectID.flatMap { id in
            model.projects.first(where: { $0.id == id })
        }

        let selectedAttr = comparisonAttributedText(for: selectedProject, mode: mode.wrappedValue)
        let comparedAgainstProject = comparedAgainstSlot?.projectID.flatMap { id in
            model.projects.first(where: { $0.id == id })
        }
        let comparedAgainstAttr = comparedAgainstProject.map { baselineProject in
            comparisonAttributedText(for: baselineProject, mode: comparedAgainstSlot?.mode ?? mode.wrappedValue)
        }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(selectedProject?.title ?? "Choose a project")
                        .font(.headline)
                }

                Spacer()

                Menu {
                    ForEach(model.projects) { project in
                        Button(project.title) {
                            slot.wrappedValue.projectID = project.id
                        }
                    }
                } label: {
                    Label("", systemImage: "document.viewfinder")
                    .help("Select a project to display")
                }

                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this draft column")
                }
            }

            HStack(spacing: 8) {
                ForEach(DraftComparisonMode.allCases) { item in
                    if mode.wrappedValue == item {
                        Button {
                            slot.wrappedValue.mode = item
                        } label: {
                            Text(item.title)
                                .font(.caption)
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                    } else {
                        Button {
                            slot.wrappedValue.mode = item
                        } label: {
                            Text(item.title)
                                .font(.caption)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
            }

            ScrollView {
                Group {
                    if selectedProject != nil {
                        if showDraftDiff, !isBaseline, let comparedAgainstAttr {
                            Text(diffAttributedText(from: comparedAgainstAttr, to: selectedAttr))
                        } else {
                            Text(AttributedString(selectedAttr))
                        }
                    } else {
                        Text(AttributedString(selectedAttr))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                )
            }
            .frame(width: width)
            .frame(minHeight: 500)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .alignmentGuide(.draftDocumentTop) { d in d[.top] }
        }
        .frame(width: width, alignment: .topLeading)
        .padding(5)
    }

    private func comparisonAttributedText(for project: AppModel.Project?, mode: DraftComparisonMode, baseFontSize: CGFloat = 22) -> NSAttributedString {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: UIColor.label
        ]

        guard let project else {
            return NSAttributedString(string: "Choose a project to compare.", attributes: baseAttrs)
        }

        let separator: String
        switch mode {
        case .sectioned:
            separator = "\n────────────────────────────────\n"
        case .unsectioned:
            separator = ""
        }

        let result = NSMutableAttributedString()
        for (index, section) in project.sections.enumerated() {
            if index > 0, !separator.isEmpty {
                result.append(NSAttributedString(string: separator, attributes: baseAttrs))
            }
            let styled = SectionAttributedText.attributedString(for: section, baseFontSize: baseFontSize)
            result.append(NSAttributedString(styled))
        }

        if result.length == 0 {
            return NSAttributedString(string: "(Empty project)", attributes: baseAttrs)
        }

        return result
    }

    private enum DraftDiffOperation {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    private func diffAttributedText(from baseAttr: NSAttributedString, to targetAttr: NSAttributedString) -> AttributedString {
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

    private func sentencesAreSimilar(_ a: String, _ b: String) -> Bool {
        let aTokens = contentWordTokens(in: a)
        let bTokens = contentWordTokens(in: b)
        guard !aTokens.isEmpty, !bTokens.isEmpty else { return false }

        let diff = bTokens.difference(from: aTokens)
        let lcsLength = aTokens.count - diff.removals.count
        let denominator = max(aTokens.count, bTokens.count)
        guard denominator > 0 else { return false }
        return Double(lcsLength) / Double(denominator) >= 0.4
    }

    private func contentWordTokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func appendWordLevelDiff(
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

    private func applyDiffOverlay(
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

    private func wordTokens(in text: String) -> [String] {
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

    private func sentenceChunks(in text: String) -> [String] {
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

    private func diffOperations(from baseTokens: [String], to targetTokens: [String]) -> [DraftDiffOperation] {
        let difference = targetTokens.difference(from: baseTokens)
        let removals: [CollectionDifference<String>.Change] = difference.removals
        let insertions: [CollectionDifference<String>.Change] = difference.insertions

        var operations: [DraftDiffOperation] = []
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

    private func changeOffset(_ change: CollectionDifference<String>.Change) -> Int {
        switch change {
        case .insert(let offset, _, _):
            return offset
        case .remove(let offset, _, _):
            return offset
        }
    }
}

struct GraveyardWindowScene: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedGraveyardItem: AppModel.DeletedSection?
    let projectID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if projectGraveyardItems.isEmpty {
                    ContentUnavailableView(
                        "Graveyard is empty",
                        systemImage: "trash",
                        description: Text("Deleted sections for this project will appear here.")
                    )
                } else {
                    List {
                        ForEach(projectGraveyardItems) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(SectionAttributedText.attributedString(for: item.section, limit: 600, baseFontSize: 17))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 10) {
                                    Button("View") {
                                        selectedGraveyardItem = item
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Restore") {
                                        model.restoreSectionFromGraveyard(item.id)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Delete Permanently", role: .destructive) {
                                        model.removeFromGraveyardPermanently(item.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Graveyard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(projectTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismissWindow(id: "graveyard-window")
                    }
                }
            }
        }
        .sheet(item: $selectedGraveyardItem) { item in
            GraveyardSectionDetailView(item: item)
        }
    }

    private var projectTitle: String {
        model.projects.first(where: { $0.id == projectID })?.title ?? "Project"
    }

    private var projectGraveyardItems: [AppModel.DeletedSection] {
        model.sectionGraveyard
            .filter { $0.projectID == projectID }
            .sorted { $0.deletedAt > $1.deletedAt }
    }
}

struct GraveyardSectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: AppModel.DeletedSection

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Text(item.projectTitle)
                    //     .font(.headline)

                    Text(SectionAttributedText.attributedString(for: item.section, baseFontSize: 18))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppModel())
    }
}

