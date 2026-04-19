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
        ZStack(alignment: .topLeading) {
            // Main content
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("ReViser")
                        .font(.largeTitle)
                        .bold()
                    Text("A spatial visualization editing application")
                        .foregroundStyle(.secondary)
                }

                // Search field for project titles
                TextField("Search projects", text: $model.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 600)

                // Projects list
                if model.filteredProjects.isEmpty {
                    ContentUnavailableView("No Projects", systemImage: "doc.on.doc", description: Text("Import a document to create a project."))
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.filteredProjects) { project in
                                NavigationLink(destination: ProjectDetailView(projectID: project.id)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(project.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(model.previewText(for: project))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: 800, alignment: .leading)
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

            // Floating breakthrough menu button (top-left)
            Menu {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Document", systemImage: "square.and.arrow.up")
                }

                Button {
                    openWindow(id: "compare-window")
                } label: {
                    Label("Compare Drafts", systemImage: "rectangle.2.swap")
                }

                Button {
                    openWindow(id: "graveyard-window")
                } label: {
                    Label {
                        Text("View Graveyard")
                    } icon: { // idk sizing weird here todo
                        Image("crumpled-paper", bundle: .radixUI)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    }
                }
            } label: {
                // Hamburger icon only; background fully blends
                Image(systemName: "line.3.horizontal")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(8)
            }
            // Slight offset down and right
            .padding(.top, 20)
            .padding(.leading, 20)
            .background(.clear)
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
        onChooseProject: @escaping (UUID) -> Void
    ) -> some View {
        let selectedProject = projectID.flatMap { id in
            model.projects.first(where: { $0.id == id })
        }

        let selectedText = comparisonText(for: selectedProject, mode: mode.wrappedValue)

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
                Text(selectedText)
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

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(Empty project)" : trimmed
    }
}

struct GraveyardWindowScene: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedGraveyardItem: AppModel.DeletedSection?

    var body: some View {
        NavigationStack {
            Group {
                if model.sectionGraveyard.isEmpty {
                    ContentUnavailableView(
                        "Graveyard is empty",
                        systemImage: "trash",
                        description: Text("Deleted sections will appear here.")
                    )
                } else {
                    List {
                        ForEach(groupedGraveyard, id: \.projectID) { group in
                            SwiftUI.Section {
                                ForEach(group.items) { item in
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
                            } header: {
                                Text(group.projectTitle)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Graveyard")
            .toolbar {
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

    private var groupedGraveyard: [(projectID: UUID, projectTitle: String, items: [AppModel.DeletedSection])] {
        let groupedByProject = Dictionary(grouping: model.sectionGraveyard, by: \.projectID)

        return groupedByProject
            .compactMap { projectID, items in
                guard let first = items.first else { return nil }
                return (
                    projectID: projectID,
                    projectTitle: first.projectTitle,
                    items: items.sorted { $0.deletedAt > $1.deletedAt }
                )
            }
            .sorted {
                let lhsDate = $0.items.first?.deletedAt ?? .distantPast
                let rhsDate = $1.items.first?.deletedAt ?? .distantPast
                return lhsDate > rhsDate
            }
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

