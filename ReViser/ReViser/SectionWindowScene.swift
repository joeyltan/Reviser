import SwiftUI
import UIKit

struct SectionWindowScene: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    @State private var calculatedHeight: CGFloat = 200

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                if let binding = sectionBinding() {
                    TextKitView(
                        text: binding,
                        splitMode: false,
                        snappedY: .constant(0),
                        onSplit: { _ in },
                        onAttach: { _ in },
                        onSelectionChange: { _ in },
                        calculatedHeight: $calculatedHeight
                    )
                    .frame(height: min(calculatedHeight, max(240, proxy.size.height - 40)))
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Section not found", systemImage: "doc")
                }
            }
            .padding(50)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Section")
    }

    private func sectionBinding() -> Binding<String>? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }) else { return nil }
        return Binding<String>(
            get: {
                guard let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return "" }
                return model.projects[projectIndex].sections[sectionIndex].text
            },
            set: { newValue in
                guard let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return }
                var sections = model.projects[projectIndex].sections
                sections[sectionIndex].text = newValue
                let projectID = model.projects[projectIndex].id
                model.updateProjectSections(id: projectID, sections: sections)
            }
        )
    }
}

