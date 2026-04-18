import SwiftUI
import RadixUI
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

// let restitchedPDFType = UTType(exportedAs: "com.reviser.restitched-pdf", conformingTo: .pdf)

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var sections: [Section] = []
    @State private var textViews: [UUID: UITextView] = [:]
    @State private var snappedY: CGFloat = 0
    @State private var showToolbar: Bool = true
    @State private var splitMode: Bool = false
    @State private var windowMode: Bool = false
    @State private var showingRestitchedManuscript: Bool = false
    // @State private var showingRestitchedPDFExport: Bool = false
    @State private var showingRestitchedDocxExport: Bool = false
    // @State private var restitchedPDFDocument = RestitchedManuscriptPDFDocument(text: "")
    @State private var restitchedDocxDocument = RestitchedManuscriptDocxDocument(text: "")

    @State private var activeSectionID: UUID?
    @State private var caretIndexBySection: [UUID: Int] = [:]
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var visibleActionSectionIDs: Set<UUID> = []
    @State private var visibleNoteSectionIDs: Set<UUID> = []
    @State private var visibleNoteOptionsSectionIDs: Set<UUID> = []
    @State private var visibleResolvedNoteSectionIDs: Set<UUID> = []
    @State private var revealedResolveNoteKey: String? = nil
    @State private var noteDraftBySection: [UUID: String] = [:]

    let projectID: UUID

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectID }) {
            HStack(spacing: 0) {
                toolbarView
                toggleButton
                if showingRestitchedManuscript {
                    restitchedManuscriptView(project: project)
                } else {
                    mainContentView(project: project)
                }
            }
            .onAppear {
                initializeSections(from: project)
                windowMode = model.isSectionsWindowOpen
            }
            .onChange(of: windowMode) { _, isOn in
                if model.isSectionsWindowOpen != isOn {
                    model.isSectionsWindowOpen = isOn
                }
                if isOn {
                    openWindow(id: "sections-window")
                } else {
                    dismissWindow(id: "sections-window")
                }
            }
            .onChange(of: model.isSectionsWindowOpen) { _, isOpen in
                if windowMode != isOpen {
                    windowMode = isOpen
                }
            }
            .onChange(of: sections) { _, newSections in
                model.updateProjectSections(id: projectID, sections: newSections)
            }
            .onChange(of: project.sections) { _, updatedSections in
                sections = updatedSections
            }
            // .fileExporter(
            //     isPresented: $showingRestitchedPDFExport,
            //     document: restitchedPDFDocument,
            //     contentType: restitchedPDFType,
            //     defaultFilename: "\(project.title)-restitched.pdf"
            // ) { _ in }
            .fileExporter(
                isPresented: $showingRestitchedDocxExport,
                document: restitchedDocxDocument,
                contentType: UTType(filenameExtension: "docx")!,
                defaultFilename: "\(project.title)-restitched.docx"
            ) { _ in }
        } else {
            Text("Project not found")
        }
    }

    @ViewBuilder
    private var toolbarView: some View {
        if showToolbar {
            VStack {
                Button {
                    splitAtCurrentCaret()
                } label: {
                    Image("scissors", bundle: .radixUI)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(splitMode ? .blue : .gray)
                }
                .help("Split text")
                Button {
                    windowMode.toggle()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(windowMode ? .blue : .gray)
                }
                .help("Window section mode")

                Button {
                    showingRestitchedManuscript.toggle()
                } label: {
                    Image(systemName: "doc.text")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(showingRestitchedManuscript ? .blue : .gray)
                }
                .help(showingRestitchedManuscript ? "Close restitched manuscript" : "View restitched manuscript")

                Button {
                    model.noteMode.toggle()
                    if !model.noteMode {
                        visibleNoteSectionIDs.removeAll()
                        visibleNoteOptionsSectionIDs.removeAll()
                        visibleResolvedNoteSectionIDs.removeAll()
                    }
                } label: {
                    Image(systemName: "note.text.badge.plus")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(model.noteMode ? .blue : .gray)
                }
                .help(model.noteMode ? "Exit notes mode" : "Add notes mode")
                Spacer()
            }
            .frame(width: 60)
            .padding()
            .background(Color(white: 0.95))
        }
    }

    @ViewBuilder
    private var toggleButton: some View {
        Button {
            showToolbar.toggle()
        } label: {
            Image(systemName: showToolbar ? "chevron.left" : "chevron.right")
        }
        .frame(width: 30)
    }

    @ViewBuilder
    private func mainContentView(project: AppModel.Project) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section: section, index: index)
                    }
                }
                .padding(40)
            }
            
            if splitMode {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: snappedY))
                    path.addLine(to: CGPoint(x: 2000, y: snappedY))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(.gray)
                .allowsHitTesting(false)
            }
        }
    }

    private func initializeSections(from project: AppModel.Project) {
        sections = project.sections.isEmpty
            ? [Section(id: UUID(), text: "")]
            : project.sections
    }

    private func restitchedManuscriptText() -> String {
        sections
            .map(\.text)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restitchedSectionTexts() -> [String] {
        sections.map(\.text)
    }

    @ViewBuilder
    private func restitchedManuscriptView(project: AppModel.Project) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Restitched Manuscript")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(project.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    // Button {
                    //     restitchedPDFDocument = RestitchedManuscriptPDFDocument(sections: restitchedSectionTexts())
                    //     showingRestitchedPDFExport = true
                    // } label: {
                    //     Label("Export as PDF", systemImage: "doc.richtext")
                    // }

                    Button {
                        restitchedDocxDocument = RestitchedManuscriptDocxDocument(text: restitchedManuscriptText())
                        showingRestitchedDocxExport = true
                    } label: {
                        Label("Export as DOCX", systemImage: "doc.text")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingRestitchedManuscript = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(restitchedManuscriptText().isEmpty ? "(Empty project)" : restitchedManuscriptText())
                    .font(.system(size: 24))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
        }
        .padding(24)
    }
    
    @ViewBuilder
    func sectionView(section: Section, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                TextKitView(
                    text: binding(for: section),
                    splitMode: splitMode,
                    snappedY: $snappedY,
                    onSplit: { y in
                        splitSection(id: section.id, y: y)
                    },
                    onAttach: { view in
                        textViews[section.id] = view
                    },
                    onSelectionChange: { caret in
                        activeSectionID = section.id
                        caretIndexBySection[section.id] = caret
                    },
                    calculatedHeight: Binding(
                        get: { sectionHeights[section.id] ?? 100 },
                        set: { sectionHeights[section.id] = $0 }
                    )
                )
                .multilineTextAlignment(.leading)
                .frame(height: sectionHeights[section.id] ?? 100)
                .frame(maxWidth: .infinity)

                if model.noteMode {
                    sectionNotesView(sectionID: section.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 8) {
                Text("\(index + 1)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Button {
                    if visibleActionSectionIDs.contains(section.id) {
                        visibleActionSectionIDs.remove(section.id)
                    } else {
                        visibleActionSectionIDs.insert(section.id)
                    }
                } label: { // consider changing ellipsis
                    Image(systemName: visibleActionSectionIDs.contains(section.id) ? "chevron.up.circle" : "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help(visibleActionSectionIDs.contains(section.id) ? "Hide actions" : "Show actions")
                .padding(.top, 6) // for spacing between the section number and tool buttons

                if visibleActionSectionIDs.contains(section.id) {
                    VStack(spacing: 10) {
                        Button {
                            openWindow(id: "section-window", value: section.id)
                        } label: {
                            Image(systemName: "rectangle.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Open this section in a window")

                        Button(role: .destructive) {
                            deleteSection(id: section.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundStyle(.red)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Delete this section")
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private func sectionNotesView(sectionID: UUID) -> some View {
        let notes = sections.first(where: { $0.id == sectionID })?.notes ?? []
        let resolvedNotes = sections.first(where: { $0.id == sectionID })?.resolvedNotes ?? []

        VStack(alignment: .leading, spacing: 8) {
            if notes.isEmpty {
                Text("No notes yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(notes.enumerated()), id: \.offset) { noteIndex, note in
                    HStack(alignment: .top, spacing: 8) {
                        Text("• \(note)")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        let resolveKey = "\(sectionID.uuidString)-\(noteIndex)"

                        Button {
                            if revealedResolveNoteKey == resolveKey {
                                resolveNote(sectionID: sectionID, noteIndex: noteIndex)
                                revealedResolveNoteKey = nil
                            } else {
                                revealedResolveNoteKey = resolveKey
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(width: 28, height: 28)

                                if revealedResolveNoteKey == resolveKey {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(revealedResolveNoteKey == resolveKey ? "Mark note as resolved" : "Show resolve button")
                    }
                }
            }

            Button {
                if visibleNoteOptionsSectionIDs.contains(sectionID) {
                    visibleNoteOptionsSectionIDs.remove(sectionID)
                    visibleNoteSectionIDs.remove(sectionID)
                    visibleResolvedNoteSectionIDs.remove(sectionID)
                } else {
                    visibleNoteOptionsSectionIDs.insert(sectionID)
                }
            } label: {
                Image(systemName: visibleNoteOptionsSectionIDs.contains(sectionID) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(visibleNoteOptionsSectionIDs.contains(sectionID) ? "Hide note options" : "Show note options")
            .frame(maxWidth: .infinity, alignment: .center)

            if visibleNoteOptionsSectionIDs.contains(sectionID) {
                HStack(spacing: 12) {
                    Button {
                        if visibleNoteSectionIDs.contains(sectionID) {
                            visibleNoteSectionIDs.remove(sectionID)
                        } else {
                            visibleNoteSectionIDs.insert(sectionID)
                            visibleResolvedNoteSectionIDs.remove(sectionID)
                        }
                    } label: {
                        Label("Add Note", systemImage: "plus.bubble")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if visibleResolvedNoteSectionIDs.contains(sectionID) {
                            visibleResolvedNoteSectionIDs.remove(sectionID)
                        } else {
                            visibleResolvedNoteSectionIDs.insert(sectionID)
                            visibleNoteSectionIDs.remove(sectionID)
                        }
                    } label: {
                        Label("Resolved Notes", systemImage: "checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if visibleResolvedNoteSectionIDs.contains(sectionID) {
                if resolvedNotes.isEmpty {
                    Text("No resolved notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(resolvedNotes.enumerated()), id: \.offset) { _, note in
                        Text("• \(note)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if visibleNoteSectionIDs.contains(sectionID) {
                HStack(spacing: 8) {
                    TextField(
                        "Add a note to this section",
                        text: Binding(
                            get: { noteDraftBySection[sectionID] ?? "" },
                            set: { noteDraftBySection[sectionID] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addNote(to: sectionID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((noteDraftBySection[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    func binding(for section: Section) -> Binding<String> {
        Binding(
            get: {
                guard let idx = sections.firstIndex(where: { $0.id == section.id }) else { return "" }
                return sections[idx].text
            },
            set: { newValue in
                if let idx = sections.firstIndex(where: { $0.id == section.id }) {
                    sections[idx].text = newValue
                }
            }
        )
    }
    
    func splitSection(id: UUID, y: CGFloat) {
        guard let index = sections.firstIndex(where: { $0.id == id }),
              let textView = textViews[id] else { return }

        let text = sections[index].text
        let lm = textView.layoutManager

        let insetTop = textView.textContainerInset.top
        let localY = y + textView.contentOffset.y - insetTop

        var glyphIndex = 0
        var lineY: CGFloat = 0
        var charIndex = 0

        while glyphIndex < lm.numberOfGlyphs {
            var lineRange = NSRange()

            let rect = lm.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange
            )

            if localY < lineY + rect.height {
                charIndex = lineRange.location
                break
            }

            lineY += rect.height
            glyphIndex = lineRange.location + lineRange.length
        }

        let splitIdx = text.index(text.startIndex, offsetBy: charIndex)

        let first = String(text[..<splitIdx])
        var second = String(text[splitIdx...])
        print("first", first)
        print("second", second)

        if second.hasPrefix("\n") {
            second.removeFirst()
        }

        // Replace section with two new ones
        sections.remove(at: index)

        if !first.isEmpty {
            sections.insert(Section(id: UUID(), text: first), at: index)
        }

        if !second.isEmpty {
            sections.insert(Section(id: UUID(), text: second), at: index + (first.isEmpty ? 0 : 1))
        }
    }

    func splitAtCurrentCaret() {
        guard let id = activeSectionID,
              let index = sections.firstIndex(where: { $0.id == id }),
              let caret = caretIndexBySection[id] else { return }

        let text = sections[index].text
        let safeCaret = min(max(caret, 0), text.count)
        let splitIdx = text.index(text.startIndex, offsetBy: safeCaret)

        let first = String(text[..<splitIdx])
        let second = String(text[splitIdx...])

        sections.remove(at: index)
        if !first.isEmpty {
            sections.insert(Section(id: UUID(), text: first), at: index)
        }
        if !second.isEmpty {
            sections.insert(Section(id: UUID(), text: second), at: index + (first.isEmpty ? 0 : 1))
        }
    }

    func deleteSection(id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }

        let sectionToDelete = sections[index]
        model.moveSectionToGraveyard(
            projectID: projectID,
            section: sectionToDelete,
            originalIndex: index
        )

        sections.remove(at: index)
        textViews[id] = nil
        sectionHeights[id] = nil
        caretIndexBySection[id] = nil
        visibleNoteOptionsSectionIDs.remove(id)
        visibleNoteSectionIDs.remove(id)
        visibleResolvedNoteSectionIDs.remove(id)
        noteDraftBySection[id] = nil

        if activeSectionID == id {
            activeSectionID = sections.first?.id
        }

        if sections.isEmpty {
            let newSection = Section(id: UUID(), text: "")
            sections = [newSection]
            activeSectionID = newSection.id
        }
    }

    func addNote(to sectionID: UUID) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return }

        let draft = (noteDraftBySection[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }

        sections[idx].notes.append(draft)
        noteDraftBySection[sectionID] = ""
    }

    func resolveNote(sectionID: UUID, noteIndex: Int) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }),
              sections[idx].notes.indices.contains(noteIndex) else { return }

        let note = sections[idx].notes.remove(at: noteIndex)
        sections[idx].resolvedNotes.append(note)
        revealedResolveNoteKey = nil
    }
}

struct SectionWindowsView: View {
    @Binding var sections: [Section]
    @Binding var sectionHeights: [UUID: CGFloat]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 24)], spacing: 24) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        SectionWindowCard(index: index, section: binding(for: section))
                    }
                }
                .padding(24)
            }
            .navigationTitle("Sections")
        }
    }

    private func binding(for section: Section) -> Binding<Section> {
        Binding<Section>(
            get: {
                sections.first(where: { $0.id == section.id }) ?? section
            },
            set: { newValue in
                if let i = sections.firstIndex(where: { $0.id == section.id }) {
                    sections[i] = newValue
                }
            }
        )
    }
}

struct SectionWindowCard: View {
    let index: Int
    @Binding var section: Section

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .frame(minHeight: 120)
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
}

struct TextKitView: UIViewRepresentable {
    @Binding var text: String
    var splitMode: Bool
    @Binding var snappedY: CGFloat
    var onSplit: (CGFloat) -> Void
    var onAttach: (UITextView) -> Void
    var onSelectionChange: (Int) -> Void
    @Binding var calculatedHeight: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()

        view.font = UIFont.systemFont(ofSize: 25)
        view.isScrollEnabled = true
        // when i change this to true then get the height problem, but when false then have width problem
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.widthTracksTextView = true   // wrap text to view width
        view.textContainer.lineBreakMode = .byWordWrapping
    
        view.isEditable = true
        view.isSelectable = true
        
        context.coordinator.textView = view
        DispatchQueue.main.async {
            self.onAttach(view)
            self.onSelectionChange(view.selectedRange.location)
        }
        
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
//        context.coordinator.splitMode = splitMode
//        uiView.isEditable = true
//        uiView.isSelectable = true
        
        DispatchQueue.main.async {
            let newHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)).height
            if self.calculatedHeight != newHeight {
                self.calculatedHeight = newHeight
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextKitView
        var textView: UITextView?
        var splitMode: Bool = false

        init(_ parent: TextKitView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onSelectionChange(textView.selectedRange.location)
        }
    }
}

struct Section: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var notes: [String] = []
    var resolvedNotes: [String] = []

    init(id: UUID, text: String, notes: [String] = [], resolvedNotes: [String] = []) {
        self.id = id
        self.text = text
        self.notes = notes
        self.resolvedNotes = resolvedNotes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case notes
        case resolvedNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        resolvedNotes = try container.decodeIfPresent([String].self, forKey: .resolvedNotes) ?? []
    }
}

struct RestitchedManuscriptPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var sections: [String]

    init(text: String = "") {
        self.sections = text.isEmpty ? [] : [text]
    }

    init(sections: [String]) {
        self.sections = sections
    }

    init(configuration: ReadConfiguration) throws {
        let text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        sections = text.isEmpty ? [] : [text]
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Self.makePDFData(from: sections))
    }

    private static func makePDFData(from sections: [String]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let contentRect = pageRect.insetBy(dx: 36, dy: 36)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let exportText = sections.isEmpty ? "(Empty project)" : sections.joined(separator: "")

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.paragraphSpacing = 6

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(string: exportText, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)

        return renderer.pdfData { context in
            var currentLocation = 0

            repeat {
                context.beginPage()
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageRect.height)
                cgContext.scaleBy(x: 1, y: -1)

                let path = CGPath(rect: contentRect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: currentLocation, length: 0),
                    path,
                    nil
                )
                CTFrameDraw(frame, cgContext)

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                currentLocation += visibleRange.length
                cgContext.restoreGState()

                if attributedText.length == 0 {
                    break
                }
            } while currentLocation < attributedText.length
        }
    }
}

struct RestitchedManuscriptDocxDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "docx")!] }

    var sections: [String]

    init(text: String = "") {
        self.sections = text.isEmpty ? [] : [text]
    }

    init(sections: [String]) {
        self.sections = sections
    }

    init(configuration: ReadConfiguration) throws {
        let text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        sections = text.isEmpty ? [] : [text]
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("docx")

        try Self.writeDocxArchive(sections: sections, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try Data(contentsOf: tempURL)
        return FileWrapper(regularFileWithContents: data)
    }

    private static func writeDocxArchive(sections: [String], to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let paragraphs = sections.isEmpty ? ["(Empty project)"] : sections

        let bodyXML = paragraphs.map { paragraph in
            let cleaned = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return "<w:p/>"
            }

            let runs = cleaned
                .components(separatedBy: CharacterSet.newlines)
                .enumerated()
                .map { index, line in
                    let escaped = xmlEscape(line)
                    if index == 0 {
                        return "<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
                    } else {
                        return "<w:r><w:br/><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
                    }
                }
                .joined()

            return "<w:p>\(runs)</w:p>"
        }.joined(separator: "")

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" mc:Ignorable="w14 wp14">
          <w:body>
            \(bodyXML)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """

        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        try addArchiveEntry(archive, path: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        try addArchiveEntry(archive, path: "_rels/.rels", data: Data(relsXML.utf8))
        try addArchiveEntry(archive, path: "word/document.xml", data: Data(documentXML.utf8))
    }

    private static func addArchiveEntry(_ archive: Archive, path: String, data: Data) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: position..<position + size)
        }
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

