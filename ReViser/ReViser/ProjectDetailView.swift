import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var text: String = ""
    let projectID: UUID

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(project.title)
                        .font(.largeTitle)
                        .bold()
                    // this is also scrollable
                    TextEditor(text: $text)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 300)
                }
                .padding(24)
            }
            .onAppear {
                print("proj text", project.text)
                text = project.text
            }
            .onChange(of: text) { _, newValue in
                model.updateProjectText(id: projectID, text: newValue)
            }
            .navigationTitle(project.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Project not found", systemImage: "doc", description: Text("The selected project could not be loaded."))
                .padding()
        }
    }
}

#Preview {
    let model = AppModel()
    let p = AppModel.Project(id: UUID(), title: "Sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), createdAt: .now, lastModified: .now, text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
    model.projects = [p]
    return NavigationStack {
        ProjectDetailView(projectID: p.id)
            .environment(model)
    }
}
