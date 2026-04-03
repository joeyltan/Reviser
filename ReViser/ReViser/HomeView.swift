import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingImporter = false
    @State private var isLoading = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("ReViser")
                    .font(.largeTitle)
                    .bold()
                Text("Create, import, and edit your writing in space")
                    .foregroundStyle(.secondary)
            }

            // Search field for project titles
            TextField("Search projects", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 600)

            // Import button
            Button {
                showingImporter = true
            } label: {
                Label("Import Document", systemImage: "tray.and.arrow.down")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Projects list
            if model.filteredProjects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "doc.on.doc", description: Text("Import a document to create a project."))
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.filteredProjects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(.headline)
                                Text(project.text.prefix(120))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 800, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
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
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: model.supportedContentTypes) { result in
            switch result {
            case .success(let url):
                Task { @MainActor in
                    isLoading = true
                }
                Task {
                    await model.loadDocument(from: url)
                    await MainActor.run { isLoading = false }
                }
            case .failure:
                break
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
}
