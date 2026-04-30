import SwiftUI
import UniformTypeIdentifiers
import RadixUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var isLoading = false
    @State private var projectPendingDeletion: AppModel.Project?
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
                                .contextMenu {
                                    Button(role: .destructive) {
                                        projectPendingDeletion = project
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
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
        .alert(
            "Delete \(projectPendingDeletion?.title ?? "Project")?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { project in
            Button("Cancel", role: .cancel) {
                projectPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                model.deleteProject(project.id)
                projectPendingDeletion = nil
            }
        } message: { _ in
            Text("This will permanently delete the project and all its sections. This cannot be undone.")
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
                            Text(DraftDiffEngine.diffAttributedText(from: comparedAgainstAttr, to: selectedAttr))
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

