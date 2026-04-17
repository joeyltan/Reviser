import SwiftUI
import UIKit

struct SectionWindowScene: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    @State private var calculatedHeight: CGFloat = 200
    @State private var showAddNoteBox: Bool = false
    @State private var noteDraft: String = ""

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
                    .frame(height: min(calculatedHeight, max(240, proxy.size.height - (model.noteMode ? 200 : 40))))
                    .frame(maxWidth: .infinity)

                    if model.noteMode, let notes = notesForSection() {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            if notes.isEmpty {
                                Text("No notes yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                                            Text("• \(note)")
                                                .font(.subheadline)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .frame(maxHeight: 160)
                            }

                            Button {
                                showAddNoteBox.toggle()
                            } label: {
                                Image(systemName: showAddNoteBox ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(showAddNoteBox ? "Hide add note box" : "Show add note box")
                            .frame(maxWidth: .infinity, alignment: .center)

                            if showAddNoteBox {
                                HStack(spacing: 8) {
                                    TextField("Add a note to this section", text: $noteDraft)
                                        .textFieldStyle(.roundedBorder)

                                    Button("Add") {
                                        addNote()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                } else {
                    ContentUnavailableView("Section not found", systemImage: "doc")
                }
            }
            .padding(50)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Section")
        .onChange(of: model.noteMode) { _, isOn in
            if !isOn {
                showAddNoteBox = false
                noteDraft = ""
            }
        }
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

    private func notesForSection() -> [String]? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return nil
        }

        return model.projects[projectIndex].sections[sectionIndex].notes
    }

    private func addNote() {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }

        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var sections = model.projects[projectIndex].sections
        sections[sectionIndex].notes.append(trimmed)
        let projectID = model.projects[projectIndex].id
        model.updateProjectSections(id: projectID, sections: sections)
        noteDraft = ""
    }
}

