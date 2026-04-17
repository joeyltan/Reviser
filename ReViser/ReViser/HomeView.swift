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

