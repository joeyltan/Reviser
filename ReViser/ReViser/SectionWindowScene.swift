import SwiftUI
import UIKit

struct SectionWindowScene: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    @State private var calculatedHeight: CGFloat = 200
    @State private var showNoteOptions: Bool = false
    @State private var showAddNoteBox: Bool = false
    @State private var showResolvedNotes: Bool = false
    @State private var noteDraft: String = ""
    @State private var editingNoteIndices: Set<Int> = []
    @State private var revealedNoteActionIndex: Int? = nil

    private var sectionTitle: String {
        guard let sectionNumber = sectionNumber else { return "Section" }
        return "Section \(sectionNumber)"
    }

    private var sectionNumber: Int? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return nil
        }

        return sectionIndex + 1
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                if let binding = sectionBinding(), let currentSection = currentSection() {

                    if let sectionNumber {
                        Text("\(sectionNumber)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.secondary.opacity(0.12)))
                            .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }

                    TextKitView(
                        text: binding,
                        textColors: currentSection.colors,
                        textHighlights: currentSection.highlights,
                        textFontTypes: currentSection.fontTypes,
                        textFontSizes: currentSection.fontSizes,
                        textBoldStyles: currentSection.boldStyles,
                        textItalicStyles: currentSection.italicStyles,
                        textUnderlineStyles: currentSection.underlineStyles,
                        textStrikethroughStyles: currentSection.strikethroughStyles,
                        splitMode: false,
                        snappedY: .constant(0),
                        onSplit: { _ in },
                        onAttach: { _ in },
                        onSelectionChange: { _,_  in },
                        calculatedHeight: $calculatedHeight
                    )
                    .frame(height: min(calculatedHeight, max(240, proxy.size.height - (model.noteMode ? 200 : 40))))
                    .frame(maxWidth: .infinity)

                    if model.noteMode, let notes = notesForSection() {
                        let resolvedNotes = resolvedNotesForSection() ?? []

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
                                        ForEach(Array(notes.indices), id: \.self) { noteIndex in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)

                                                if editingNoteIndices.contains(noteIndex), let binding = noteBinding(noteIndex: noteIndex) {
                                                    TextField("Edit note", text: binding)
                                                        .textFieldStyle(.roundedBorder)
                                                        .font(.subheadline)
                                                } else {
                                                    Text(notes[noteIndex])
                                                        .font(.subheadline)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }

                                                HStack(spacing: 6) {
                                                    if revealedNoteActionIndex == noteIndex {
                                                        Button {
                                                            if editingNoteIndices.contains(noteIndex) {
                                                                editingNoteIndices.remove(noteIndex)
                                                            } else {
                                                                editingNoteIndices.insert(noteIndex)
                                                            }
                                                        } label: {
                                                            Group {
                                                                if editingNoteIndices.contains(noteIndex) {
                                                                    Text("Save")
                                                                        .font(.caption)
                                                                        .foregroundStyle(.secondary)
                                                                } else {
                                                                    Image(systemName: "pencil")
                                                                        .font(.system(size: 16))
                                                                        .foregroundStyle(.secondary)
                                                                }
                                                            }
                                                            .frame(width: 44, height: 28)
                                                            .background(
                                                                RoundedRectangle(cornerRadius: 14)
                                                                    .fill(Color.secondary.opacity(0.08))
                                                            )
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help(editingNoteIndices.contains(noteIndex) ? "Finish editing note" : "Edit note")

                                                        Button {
                                                            resolveNote(noteIndex: noteIndex)
                                                            revealedNoteActionIndex = nil
                                                        } label: {
                                                            ZStack {
                                                                Circle()
                                                                    .fill(Color.secondary.opacity(0.08))
                                                                    .frame(width: 28, height: 28)

                                                                Image(systemName: "checkmark")
                                                                    .font(.system(size: 16))
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Mark note as resolved")
                                                    }

                                                    Spacer(minLength: 0)

                                                    Button {
                                                        if revealedNoteActionIndex == noteIndex {
                                                            revealedNoteActionIndex = nil
                                                        } else {
                                                            revealedNoteActionIndex = noteIndex
                                                        }
                                                    } label: {
                                                        ZStack {
                                                            Circle()
                                                                .fill(Color.secondary.opacity(0.18))
                                                                .frame(width: 28, height: 28)
                                                            // have no image for this
                                                            // Image(systemName: revealedNoteActionIndex == noteIndex ? "chevron.up" : "chevron.down")
                                                            //     .font(.system(size: 12, weight: .semibold))
                                                            //     .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help(revealedNoteActionIndex == noteIndex ? "Hide note actions" : "Show note actions")
                                                }
                                                .frame(width: 120, alignment: .trailing)
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if revealedNoteActionIndex == noteIndex {
                                                    revealedNoteActionIndex = nil
                                                } else {
                                                    revealedNoteActionIndex = noteIndex
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 160)
                            }

                            Button {
                                if showNoteOptions {
                                    showNoteOptions = false
                                    showAddNoteBox = false
                                    showResolvedNotes = false
                                } else {
                                    showNoteOptions = true
                                }
                            } label: {
                                Image(systemName: showNoteOptions ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(showNoteOptions ? "Hide note options" : "Show note options")
                            .frame(maxWidth: .infinity, alignment: .center)

                            if showNoteOptions {
                                HStack(spacing: 12) {
                                    Button {
                                        if showAddNoteBox {
                                            showAddNoteBox = false
                                        } else {
                                            showAddNoteBox = true
                                            showResolvedNotes = false
                                        }
                                    } label: {
                                        Label("Add Note", systemImage: "plus.bubble")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        if showResolvedNotes {
                                            showResolvedNotes = false
                                        } else {
                                            showResolvedNotes = true
                                            showAddNoteBox = false
                                        }
                                    } label: {
                                        Label("Resolved Notes", systemImage: "checkmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        clearAllNotes()
                                    } label: {
                                        Label("Clear All", systemImage: "xmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(notes.isEmpty && resolvedNotes.isEmpty)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }

                            if showResolvedNotes {
                                if resolvedNotes.isEmpty {
                                    Text("No resolved notes")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(Array(resolvedNotes.enumerated()), id: \.offset) { _, note in
                                                Text("• \(note)")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 120)
                                }
                            }

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
        .navigationTitle(sectionTitle)
        .onChange(of: model.noteMode) { _, isOn in
            if !isOn {
                showNoteOptions = false
                showAddNoteBox = false
                showResolvedNotes = false
                noteDraft = ""
                editingNoteIndices.removeAll()
                revealedNoteActionIndex = nil
            }
        }
    }

    private func currentSection() -> Section? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return nil
        }

        return model.projects[projectIndex].sections[sectionIndex]
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

    private func resolvedNotesForSection() -> [String]? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return nil
        }

        return model.projects[projectIndex].sections[sectionIndex].resolvedNotes
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
        editingNoteIndices.removeAll()
        revealedNoteActionIndex = nil
    }

    private func resolveNote(noteIndex: Int) {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }

        var sections = model.projects[projectIndex].sections
        guard sections[sectionIndex].notes.indices.contains(noteIndex) else { return }

        let note = sections[sectionIndex].notes.remove(at: noteIndex)
        sections[sectionIndex].resolvedNotes.append(note)

        let projectID = model.projects[projectIndex].id
        model.updateProjectSections(id: projectID, sections: sections)
        editingNoteIndices.removeAll()
    }

    private func clearAllNotes() {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }),
              let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }

        var sections = model.projects[projectIndex].sections
        sections[sectionIndex].notes.removeAll()
        sections[sectionIndex].resolvedNotes.removeAll()

        let projectID = model.projects[projectIndex].id
        model.updateProjectSections(id: projectID, sections: sections)

        noteDraft = ""
        showAddNoteBox = false
        showResolvedNotes = false
        editingNoteIndices.removeAll()
        revealedNoteActionIndex = nil
    }

    private func noteBinding(noteIndex: Int) -> Binding<String>? {
        guard let projectIndex = model.projects.firstIndex(where: { $0.sections.contains(where: { $0.id == sectionID }) }) else {
            return nil
        }

        return Binding<String>(
            get: {
                guard let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }),
                      model.projects[projectIndex].sections[sectionIndex].notes.indices.contains(noteIndex) else {
                    return ""
                }
                return model.projects[projectIndex].sections[sectionIndex].notes[noteIndex]
            },
            set: { newValue in
                guard let sectionIndex = model.projects[projectIndex].sections.firstIndex(where: { $0.id == sectionID }),
                      model.projects[projectIndex].sections[sectionIndex].notes.indices.contains(noteIndex) else {
                    return
                }

                var sections = model.projects[projectIndex].sections
                sections[sectionIndex].notes[noteIndex] = newValue
                let projectID = model.projects[projectIndex].id
                model.updateProjectSections(id: projectID, sections: sections)
            }
        )
    }
}

