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
        let operations = diffOperations(from: diffTokens(in: baseText), to: diffTokens(in: targetText))
        let result = NSMutableAttributedString()

        for operation in operations {
            switch operation {
            case .equal(let token):
                appendDiffToken(token, to: result)
            case .insert(let token):
                appendDiffToken(
                    token,
                    to: result,
                    foregroundColor: UIColor.systemGreen,
                    backgroundColor: UIColor.systemGreen.withAlphaComponent(0.24)
                )
            case .delete(let token):
                appendDiffToken(
                    token,
                    to: result,
                    foregroundColor: UIColor.systemRed,
                    backgroundColor: UIColor.systemRed.withAlphaComponent(0.18),
                    strikethrough: true
                )
            }
        }

        return AttributedString(result)
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

    private func diffTokens(in text: String) -> [String] {
        guard let firstCharacter = text.first else { return [] }

        var tokens: [String] = []
        var tokenStart = text.startIndex
        var tokenIsWhitespace = firstCharacter.isWhitespace
        var index = text.index(after: tokenStart)

        while index < text.endIndex {
            let isWhitespace = text[index].isWhitespace
            if isWhitespace != tokenIsWhitespace {
                tokens.append(String(text[tokenStart..<index]))
                tokenStart = index
                tokenIsWhitespace = isWhitespace
            }
            index = text.index(after: index)
        }

        tokens.append(String(text[tokenStart..<text.endIndex]))
        return tokens
    }

    private func diffOperations(from baseTokens: [String], to targetTokens: [String]) -> [DraftDiffOperation] {
        var operations: [DraftDiffOperation] = []

        func recurse(_ baseStart: Int, _ baseEnd: Int, _ targetStart: Int, _ targetEnd: Int) {
            var baseStartIndex = baseStart
            var targetStartIndex = targetStart
            var baseEndIndex = baseEnd
            var targetEndIndex = targetEnd

            while baseStartIndex < baseEndIndex,
                  targetStartIndex < targetEndIndex,
                  baseTokens[baseStartIndex] == targetTokens[targetStartIndex] {
                operations.append(.equal(baseTokens[baseStartIndex]))
                baseStartIndex += 1
                targetStartIndex += 1
            }

            while baseStartIndex < baseEndIndex,
                  targetStartIndex < targetEndIndex,
                  baseTokens[baseEndIndex - 1] == targetTokens[targetEndIndex - 1] {
                baseEndIndex -= 1
                targetEndIndex -= 1
            }

            if baseStartIndex >= baseEndIndex {
                for index in targetStartIndex..<targetEndIndex {
                    operations.append(.insert(targetTokens[index]))
                }

                for index in baseEndIndex..<baseEnd {
                    operations.append(.equal(baseTokens[index]))
                }
                return
            }

            if targetStartIndex >= targetEndIndex {
                for index in baseStartIndex..<baseEndIndex {
                    operations.append(.delete(baseTokens[index]))
                }

                for index in baseEndIndex..<baseEnd {
                    operations.append(.equal(baseTokens[index]))
                }
                return
            }

            let baseMiddle = baseStartIndex..<baseEndIndex
            let targetMiddle = targetStartIndex..<targetEndIndex

            if let anchor = uniqueCommonAnchor(in: baseMiddle, and: targetMiddle, baseTokens: baseTokens, targetTokens: targetTokens) {
                recurse(baseStartIndex, anchor.baseIndex, targetStartIndex, anchor.targetIndex)
                operations.append(.equal(baseTokens[anchor.baseIndex]))
                recurse(anchor.baseIndex + 1, baseEndIndex, anchor.targetIndex + 1, targetEndIndex)

                for index in baseEndIndex..<baseEnd {
                    operations.append(.equal(baseTokens[index]))
                }
                return
            }

            for index in baseStartIndex..<baseEndIndex {
                operations.append(.delete(baseTokens[index]))
            }

            for index in targetStartIndex..<targetEndIndex {
                operations.append(.insert(targetTokens[index]))
            }

            for index in baseEndIndex..<baseEnd {
                operations.append(.equal(baseTokens[index]))
            }
        }

        recurse(0, baseTokens.count, 0, targetTokens.count)
        return operations
    }

    private func uniqueCommonAnchor(
        in baseRange: Range<Int>,
        and targetRange: Range<Int>,
        baseTokens: [String],
        targetTokens: [String]
    ) -> (baseIndex: Int, targetIndex: Int)? {
        var baseCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]

        for index in baseRange {
            baseCounts[baseTokens[index], default: 0] += 1
        }

        for index in targetRange {
            targetCounts[targetTokens[index], default: 0] += 1
        }

        for baseIndex in baseRange {
            let token = baseTokens[baseIndex]
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard baseCounts[token] == 1, targetCounts[token] == 1 else { continue }

            if let targetIndex = targetRange.firstIndex(where: { targetTokens[$0] == token }) {
                return (baseIndex, targetIndex)
            }
        }

        return nil
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

