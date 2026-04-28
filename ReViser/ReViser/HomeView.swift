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

struct CompareDraftsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var leftProjectID: UUID?
    @State private var rightProjectID: UUID?
    @State private var leftMode: DraftComparisonMode = .sectioned
    @State private var rightMode: DraftComparisonMode = .unsectioned
    @State private var showDraftDiff: Bool = true

    var body: some View {
        NavigationStack {
            Group {
                if model.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "doc.on.doc",
                        description: Text("Import two projects to compare drafts.")
                    )
                } else {
                    GeometryReader { proxy in
                        let sideWidth = max(320, (proxy.size.width - 72) / 2)

                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 24) {
                                compareColumn(
                                    title: "Left Draft",
                                    projectID: leftProjectID,
                                    mode: $leftMode,
                                    width: sideWidth,
                                    onChooseProject: { leftProjectID = $0 }
                                )

                                compareColumn(
                                    title: "Right Draft",
                                    projectID: rightProjectID,
                                    mode: $rightMode,
                                    width: sideWidth,
                                    comparedAgainstProjectID: leftProjectID,
                                    comparedAgainstMode: leftMode,
                                    onChooseProject: { rightProjectID = $0 }
                                )
                            }
                            .padding(24)
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

        if leftProjectID == nil {
            leftProjectID = model.projects.first?.id
        }

        if rightProjectID == nil {
            rightProjectID = model.projects.dropFirst().first?.id ?? model.projects.first?.id
        }
    }

    @ViewBuilder
    private func compareColumn(
        title: String,
        projectID: UUID?,
        mode: Binding<DraftComparisonMode>,
        width: CGFloat,
        comparedAgainstProjectID: UUID? = nil,
        comparedAgainstMode: DraftComparisonMode? = nil,
        onChooseProject: @escaping (UUID) -> Void
    ) -> some View {
        let selectedProject = projectID.flatMap { id in
            model.projects.first(where: { $0.id == id })
        }

        let selectedText = comparisonText(for: selectedProject, mode: mode.wrappedValue)
        let comparedAgainstProject = comparedAgainstProjectID.flatMap { id in
            model.projects.first(where: { $0.id == id })
        }
        let comparedAgainstText = comparedAgainstProject.map { baselineProject in
            comparisonText(for: baselineProject, mode: comparedAgainstMode ?? mode.wrappedValue)
        }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProject?.title ?? "Choose a project")
                        .font(.headline)
                }

                Spacer()

                Menu {
                    ForEach(model.projects) { project in
                        Button(project.title) {
                            onChooseProject(project.id)
                        }
                    }
                } label: {
                    Label("", systemImage: "document.viewfinder")
                    .help("Select a project to display")
                }
            }

            HStack(spacing: 8) {
                ForEach(DraftComparisonMode.allCases) { item in
                    if mode.wrappedValue == item {
                        Button {
                            mode.wrappedValue = item
                        } label: {
                            Text(item.title)
                                .font(.caption)
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                    } else {
                        Button {
                            mode.wrappedValue = item
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
                    if let selectedProject {
                        if showDraftDiff, let comparedAgainstText, comparedAgainstProjectID != nil {
                            Text(diffAttributedText(from: comparedAgainstText, to: selectedText))
                        } else {
                            Text(verbatim: selectedText)
                        }
                    } else {
                        Text(verbatim: selectedText)
                    }
                }
                .font(.system(size: 22))
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
        }
        .frame(width: width, alignment: .topLeading)
        .padding(5)
    }

    private func comparisonText(for project: AppModel.Project?, mode: DraftComparisonMode) -> String {
        guard let project else { return "Choose a project to compare." }

        let text: String
        switch mode {
        case .sectioned:
            text = project.sections
                .map { section in section.text }
                .joined(separator: "\n────────────────────────────────\n")
        case .unsectioned:
            text = project.sections
                .map { section in section.text }
                .joined(separator: "")
        }

        return text.isEmpty ? "(Empty project)" : text
    }

    private enum DraftDiffOperation {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    private func diffAttributedText(from baseText: String, to targetText: String) -> AttributedString {
        let baseSentences = sentenceChunks(in: baseText)
        let targetSentences = sentenceChunks(in: targetText)
        let operations = diffOperations(from: baseSentences, to: targetSentences)
        let result = NSMutableAttributedString()
        var index = 0

        while index < operations.count {
            switch operations[index] {
            case .equal(let token):
                appendDiffToken(token, to: result)
                index += 1
            case .delete(let baseChunk):
                if index + 1 < operations.count,
                   case .insert(let targetChunk) = operations[index + 1] {
                    appendWordLevelDiff(from: baseChunk, to: targetChunk, into: result)
                    index += 2
                } else {
                    appendDiffToken(
                        baseChunk,
                        to: result,
                        foregroundColor: UIColor.systemRed,
                        backgroundColor: UIColor.systemRed.withAlphaComponent(0.18),
                        strikethrough: true
                    )
                    index += 1
                }
            case .insert(let token):
                appendDiffToken(
                    token,
                    to: result,
                    foregroundColor: UIColor.systemGreen,
                    backgroundColor: UIColor.systemGreen.withAlphaComponent(0.24)
                )
                index += 1
            }
        }

        return AttributedString(result)
    }

    private func appendWordLevelDiff(from baseText: String, to targetText: String, into attributedString: NSMutableAttributedString) {
        let baseTokens = wordTokens(in: baseText)
        let targetTokens = wordTokens(in: targetText)
        let operations = diffOperations(from: baseTokens, to: targetTokens)

        for operation in operations {
            switch operation {
            case .equal(let token):
                appendDiffToken(token, to: attributedString)
            case .insert(let token):
                appendDiffToken(
                    token,
                    to: attributedString,
                    foregroundColor: UIColor.systemGreen,
                    backgroundColor: UIColor.systemGreen.withAlphaComponent(0.24)
                )
            case .delete(let token):
                appendDiffToken(
                    token,
                    to: attributedString,
                    foregroundColor: UIColor.systemRed,
                    backgroundColor: UIColor.systemRed.withAlphaComponent(0.18),
                    strikethrough: true
                )
            }
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

    private func appendDiffToken(
        _ token: String,
        to attributedString: NSMutableAttributedString,
        foregroundColor: UIColor? = nil,
        backgroundColor: UIColor? = nil,
        strikethrough: Bool = false
    ) {
        guard !token.isEmpty else { return }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let foregroundColor {
            attributes[.foregroundColor] = foregroundColor
        }
        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        if strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        attributedString.append(NSAttributedString(string: token, attributes: attributes))
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

                                Text(item.section.text.isEmpty ? "(Empty section)" : String(item.section.text.prefix(600)))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

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

                    Text(item.section.text.isEmpty ? "(Empty section)" : item.section.text)
                        .font(.body)
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

