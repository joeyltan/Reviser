import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sectionReorder = UTType(exportedAs: "com.reviser.section-reorder")
}

struct SectionsWindowScene: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var sections: [Section] = []
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var currentProjectID: UUID?
    @State private var savedSectionOrder: [UUID] = []
    @State private var hasPendingReorder: Bool = false
    
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

                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    saveCurrentOrder()
                                } label: {
                                    Label("Save Reorder", systemImage: "checkmark.circle")
                                }
                                .disabled(!hasPendingReorder)
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
            hasPendingReorder = sections.map(\.id) != savedSectionOrder
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

        savedSectionOrder = sections.map(\.id)
        hasPendingReorder = false
    }
    
    private func saveCurrentOrder() {
        guard let projectID = currentProjectID else { return }
        model.updateProjectSections(id: projectID, sections: sections)
        savedSectionOrder = sections.map(\.id)
        hasPendingReorder = false
    }
}

struct SectionsGridView: View {
    static let columns: [GridItem] = [GridItem(.adaptive(minimum: 420), spacing: 24)]
    
    @Binding var sections: [Section]
    @State private var draggedSectionID: UUID?
    @State private var expandedSectionIDs: Set<UUID> = []
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 24) {
                ForEach(Array($sections.enumerated()), id: \.element.id) { index, $section in
                    SectionsOverviewCard(
                        index: index,
                        section: $section,
                        isExpanded: expandedSectionIDs.contains(section.id),
                        onToggleExpand: {
                            withAnimation {
                                if expandedSectionIDs.contains(section.id) {
                                    expandedSectionIDs.remove(section.id)
                                } else {
                                    expandedSectionIDs.insert(section.id)
                                }
                            }
                        },
                        onDragStart: {
                            draggedSectionID = section.id

                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(
                                forTypeIdentifier: UTType.sectionReorder.identifier,
                                visibility: .all
                            ) { completion in
                                completion(Data(), nil)
                                return nil
                            }
                            return provider
                        }
                    )
                    .opacity(draggedSectionID == section.id ? 0.6 : 1.0)
                        .onDrop(
                            of: [UTType.sectionReorder],
                            delegate: SectionReorderDropDelegate(
                                targetSection: section,
                                sections: $sections,
                                draggedSectionID: $draggedSectionID
                            )
                        )
                }
            }
            .padding(24)
        }
    }
}

struct SectionsOverviewCard: View {
    let index: Int
    @Binding var section: Section
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDragStart: () -> NSItemProvider

    private let collapsedEditorHeight: CGFloat = 120
    private let collapsedCardHeight: CGFloat = 220

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 24, 240)
            let editorHeight = isExpanded ? estimatedEditorHeight(for: section.text, width: contentWidth) : collapsedEditorHeight

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .contentShape(Capsule())
                    .onDrag {
                        onDragStart()
                    }
                    .help("Drag to redorder")

                    Spacer()

                    // todo: maybe change this so that more than one seciton can be fully expanded at a time
                    Button {
                        onToggleExpand()
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help(isExpanded ? "Collapse section" : "Expand section")
                }

                HStack {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    Spacer()
                }

                TextEditor(text: $section.text)
                    .font(.system(size: 25))
                    .frame(height: editorHeight)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .frame(height: isExpanded ? expandedCardHeight(for: section.text, width: 420) : collapsedCardHeight)
    }

    private func estimatedEditorHeight(for text: String, width: CGFloat) -> CGFloat {
        let displayText = text.isEmpty ? " " : text
        let font = UIFont.systemFont(ofSize: 25)
        let rect = (displayText as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return max(collapsedEditorHeight, ceil(rect.height) + 24)
    }

    private func expandedCardHeight(for text: String, width: CGFloat) -> CGFloat {
        estimatedEditorHeight(for: text, width: width) + 96
    }
}

struct SectionReorderDropDelegate: DropDelegate {
    let targetSection: Section
    @Binding var sections: [Section]
    @Binding var draggedSectionID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedSectionID,
              draggedID != targetSection.id,
              let fromIndex = sections.firstIndex(where: { $0.id == draggedID }),
              let toIndex = sections.firstIndex(where: { $0.id == targetSection.id }) else { return }

        withAnimation {
            sections.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSectionID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [UTType.sectionReorder]) {
            draggedSectionID = nil
        }
    }
}
