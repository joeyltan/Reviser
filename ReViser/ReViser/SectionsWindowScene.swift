import SwiftUI

struct SectionsWindowScene: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var sections: [Section] = []
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var currentProjectID: UUID?
    
    var body: some View {
        Group {
            if currentProjectID != nil {
                NavigationStack {
                    SectionsGridView(sections: $sections)
                        .navigationTitle("Sections")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    model.isSectionsWindowOpen = false
                                    dismissWindow(id: "sections-window")
                                } label: {
                                    Label("Return to Text", systemImage: "arrow.left.circle")
                                }
                            }
                        }
                }
            } else {
                ContentUnavailableView("No sections", systemImage: "doc.text", description: Text("Create a project first."))
            }
        }
        .onAppear {
            model.isSectionsWindowOpen = true
            loadMostRecentProject()
        }
        .onDisappear {
            model.isSectionsWindowOpen = false
        }
        .onChange(of: sections) { _, newSections in
            updateProjectSections(newSections)
        }
    }
    
    private func loadMostRecentProject() {
        let sortedProjects = model.projects.sorted { (a: AppModel.Project, b: AppModel.Project) -> Bool in
            a.lastModified > b.lastModified
        }
        
        if let mostRecent = sortedProjects.first {
            currentProjectID = mostRecent.id
            sections = mostRecent.sections
        } else if let firstProject = model.projects.first {
            currentProjectID = firstProject.id
            sections = firstProject.sections
        } else {
            currentProjectID = nil
            sections = []
        }
    }
    
    private func updateProjectSections(_ newSections: [Section]) {
        if let projectID = currentProjectID {
            model.updateProjectSections(id: projectID, sections: newSections)
        }
    }
}

struct SectionsGridView: View {
    static let columns: [GridItem] = [GridItem(.adaptive(minimum: 420), spacing: 24)]
    
    @Binding var sections: [Section]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 24) {
                ForEach(Array($sections.enumerated()), id: \.element.id) { index, $section in
                    SectionWindowCard(index: index, section: $section)
                }
            }
            .padding(24)
        }
    }
}
