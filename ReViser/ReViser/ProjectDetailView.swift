import SwiftUI
import RadixUI
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

struct TextStyleRange: Codable, Equatable {
    var location: Int
    var length: Int
    var style: String

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct ProjectDetailView: View {
    struct ProjectEditSnapshot: Equatable {
        var sections: [Section]
        var sectionTags: [UUID: Set<String>]
        var taggedTextBySection: [UUID: [String: Set<String>]]
    }

    enum NoteDeletionAction: Equatable {
        case resolvedNote(sectionID: UUID, resolvedIndex: Int)
        case clearAll(sectionID: UUID)
    }

    enum SectionDeletionAction: Equatable {
        case section(sectionID: UUID)
    }

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
    @State private var showingRestitchedDocxExport: Bool = false
    @State private var restitchedDocxDocument = RestitchedManuscriptDocxDocument(text: "")
    @State private var showingCustomFontSizeSheet: Bool = false
    @State private var customFontSizeValue: Double = 25

    @State private var activeSectionID: UUID?
    @State private var caretIndexBySection: [UUID: Int] = [:]
    @State private var selectedLengthBySection: [UUID: Int] = [:]
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var visibleActionSectionIDs: Set<UUID> = []
    @State private var visibleNoteSectionIDs: Set<UUID> = []
    @State private var visibleNoteOptionsSectionIDs: Set<UUID> = []
    @State private var visibleResolvedNoteSectionIDs: Set<UUID> = []
    @State private var revealedResolveNoteKey: String? = nil
    @State private var revealedReorderHandleSectionID: UUID? = nil
    @State private var draggedSectionID: UUID? = nil
    @State private var noteDraftBySection: [UUID: String] = [:]
    @State private var editingNoteKeys: Set<String> = []
    @State private var pendingNoteDeletion: NoteDeletionAction? = nil
    @State private var pendingSectionDeletion: SectionDeletionAction? = nil
    @State private var openingAllSectionWindows: Bool = false
    @State private var allSectionWindowsVisible: Bool = false
    @State private var showingSectionWindowPickerSheet: Bool = false
    @State private var sectionWindowSelection: Set<UUID> = []
    @State private var sectionTags: [UUID: Set<String>] = [:]
    @State private var taggedTextBySection: [UUID: [String: Set<String>]] = [:]
    @State private var customTagCategories: Set<String> = []
    @State private var activeFilterTags: Set<String> = []
    @State private var showFilteredTimeline: Bool = false
    @State private var linkedTimelineFrames: [UUID: CGRect] = [:]
    @State private var linkedTimelineTextViewFrames: [UUID: CGRect] = [:]
    @State private var linkedTimelineSnippetPoints: [UUID: [String: [CGPoint]]] = [:]
    @State private var showingNoFilterMatchAlert: Bool = false
    @State private var showingNewTagAlert: Bool = false
    @State private var newTagName: String = ""
    @State private var tagActionSectionID: UUID?
    @State private var tagActionSectionTags: [String] = []
    @State private var tagActionTextTags: [String] = []
    @State private var projectUndoStack: [ProjectEditSnapshot] = []
    @State private var projectRedoStack: [ProjectEditSnapshot] = []
    @State private var hasInitializedSectionHistory: Bool = false
    @State private var isApplyingUndo: Bool = false
    @State private var isApplyingRedo: Bool = false
    @State private var isSyncingSectionsFromModel: Bool = false

    let projectID: UUID

    var body: some View {
        Group {
            if let project = model.projects.first(where: { $0.id == projectID }) {
                projectEditor(project: project)
            } else {
                Text("Project not found")
            }
        }
    }

    @ViewBuilder
    private func projectEditor(project: AppModel.Project) -> some View {
        mainLayout(project: project)
            .modifier(DialogsModifier(parent: self, project: project))
            .modifier(LifecycleModifier(parent: self, project: project))
    }

    @ViewBuilder
    private func mainLayout(project: AppModel.Project) -> some View {
        ZStack {
            contentRow(project: project)
            overlayLayer
        }
    }

    @ViewBuilder
    private func contentRow(project: AppModel.Project) -> some View {
        HStack(spacing: 0) {
            toolbarView
            toggleButton
            contentSwitcher(project: project)
        }
    }

    @ViewBuilder
    private func contentSwitcher(project: AppModel.Project) -> some View {
        if showingRestitchedManuscript {
            restitchedManuscriptView(project: project)
        } else {
            mainContentView(project: project)
        }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        if showingCustomFontSizeSheet {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    closeCustomFontSizePopup()
                }

            customFontSizeCenteredPopup
        }
    }

    struct DialogsModifier: ViewModifier {
        let parent: ProjectDetailView
        let project: AppModel.Project

        func body(content: Content) -> some View {
            content
                .confirmationDialog(
                    "Tag options",
                    isPresented: Binding(
                        get: { parent.tagActionSectionID != nil },
                        set: { isPresented in
                            if !isPresented {
                                parent.tagActionSectionID = nil
                                parent.tagActionSectionTags = []
                                parent.tagActionTextTags = []
                            }
                        }
                    ),
                    titleVisibility: .visible
                ) {
                    if let sectionID = parent.tagActionSectionID {
                        if !parent.tagActionSectionTags.isEmpty {
                            SwiftUI.Section("Remove section tag") {
                                ForEach(parent.tagActionSectionTags, id: \.self) { tag in
                                    Button("Delete \(tag) (Section)", role: .destructive) {
                                        parent.removeSectionTag(tag, from: sectionID)
                                    }
                                }
                            }
                        }

                        if !parent.tagActionSectionTags.isEmpty && !parent.tagActionTextTags.isEmpty {
                            Divider()
                        }

                        if !parent.tagActionTextTags.isEmpty {
                            SwiftUI.Section("Remove text tag") {
                                ForEach(parent.tagActionTextTags, id: \.self) { tag in
                                    Button("Delete \(tag) (Text)", role: .destructive) {
                                        parent.removeTextTag(tag, from: sectionID)
                                    }
                                }
                            }
                        }
                    }
                }
                .confirmationDialog(
                    parent.pendingNoteDeletionTitle,
                    isPresented: Binding(
                        get: { parent.pendingNoteDeletion != nil },
                        set: { isPresented in
                            if !isPresented {
                                parent.pendingNoteDeletion = nil
                            }
                        }
                    ),
                    titleVisibility: .visible
                ) {
                    if let pending = parent.pendingNoteDeletion {
                        switch pending {
                        case .resolvedNote(let sectionID, let resolvedIndex):
                            Button("Delete Note", role: .destructive) {
                                parent.deleteResolvedNote(sectionID: sectionID, resolvedIndex: resolvedIndex)
                                parent.pendingNoteDeletion = nil
                            }

                        case .clearAll(let sectionID):
                            Button("Clear Notes", role: .destructive) {
                                parent.clearAllNotes(in: sectionID)
                                parent.pendingNoteDeletion = nil
                            }
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        parent.pendingNoteDeletion = nil
                    }
                } message: {
                    Text(parent.pendingNoteDeletionMessage)
                }
                .confirmationDialog(
                    parent.pendingSectionDeletionTitle,
                    isPresented: Binding(
                        get: { parent.pendingSectionDeletion != nil },
                        set: { isPresented in
                            if !isPresented {
                                parent.pendingSectionDeletion = nil
                            }
                        }
                    ),
                    titleVisibility: .visible
                ) {
                    if let pending = parent.pendingSectionDeletion {
                        switch pending {
                        case .section(let sectionID):
                            Button("Delete Section", role: .destructive) {
                                parent.deleteSection(id: sectionID)
                                parent.pendingSectionDeletion = nil
                            }
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        parent.pendingSectionDeletion = nil
                    }
                } message: {
                    Text(parent.pendingSectionDeletionMessage)
                }
                .alert("No filter match", isPresented: parent.$showingNoFilterMatchAlert) {
                    Button("OK", role: .cancel) {}
                }
                .fileExporter(
                    isPresented: parent.$showingRestitchedDocxExport,
                    document: parent.restitchedDocxDocument,
                    contentType: UTType(filenameExtension: "docx")!,
                    defaultFilename: "\(project.title)-restitched.docx"
                ) { _ in }
                .sheet(isPresented: parent.$showingSectionWindowPickerSheet) {
                    SectionWindowPickerSheet(
                        sections: parent.sections,
                        selection: parent.$sectionWindowSelection,
                        onCancel: {
                            parent.showingSectionWindowPickerSheet = false
                        },
                        onConfirm: { selectedIDs in
                            parent.showingSectionWindowPickerSheet = false
                            parent.openSectionsInWindows(ids: selectedIDs)
                        }
                    )
                }
        }
    }

    struct LifecycleModifier: ViewModifier {
        let parent: ProjectDetailView
        let project: AppModel.Project

        func body(content: Content) -> some View {
            content
                .onAppear {
                    parent.handleOnAppear(project: project)
                }
                .onChange(of: parent.windowMode) { _, isOn in
                    parent.handleWindowModeChange(isOn)
                }
                .onChange(of: parent.model.isSectionsWindowOpen) { _, isOpen in
                    parent.syncWindowMode(isOpen)
                }
                .onChange(of: parent.sections) { oldSections, newSections in
                    parent.handleSectionsChange(old: oldSections, new: newSections)
                }
                .onChange(of: project.sections) { _, updatedSections in
                    parent.handleProjectSectionsChange(updatedSections)
                }
                .onChange(of: parent.sectionTags) { _, _ in
                    parent.handleTagChange()
                }
                .onChange(of: parent.taggedTextBySection) { _, _ in
                    parent.handleTagChange()
                }
                .onChange(of: parent.customTagCategories) { _, _ in
                    parent.handleTagChange()
                }
                .onChange(of: parent.activeFilterTags) { _, newFilters in
                    parent.handleFilterChange(newFilters)
                }
        }
    }

    func handleOnAppear(project: AppModel.Project) {
        projectUndoStack.removeAll()
        projectRedoStack.removeAll()
        hasInitializedSectionHistory = false
        isApplyingUndo = false
        isApplyingRedo = false
        isSyncingSectionsFromModel = true
        initializeSections(from: project)
        windowMode = model.isSectionsWindowOpen
    }

    func handleWindowModeChange(_ isOn: Bool) {
        if model.isSectionsWindowOpen != isOn {
            model.isSectionsWindowOpen = isOn
        }
        if isOn {
            openWindow(id: "sections-window")
        } else {
            dismissWindow(id: "sections-window")
        }
    }

    func syncWindowMode(_ isOpen: Bool) {
        if windowMode != isOpen {
            windowMode = isOpen
        }
    }

    func handleSectionsChange(old: [Section], new: [Section]) {
        if !hasInitializedSectionHistory {
            hasInitializedSectionHistory = true
        } else if !isApplyingUndo && !isApplyingRedo && !isSyncingSectionsFromModel && old != new {
            let snapshot = ProjectEditSnapshot(
                sections: old,
                sectionTags: sectionTags,
                taggedTextBySection: taggedTextBySection
            )
            pushUndoSnapshot(snapshot)
        }

        if isApplyingUndo { isApplyingUndo = false }
        if isApplyingRedo { isApplyingRedo = false }
        if isSyncingSectionsFromModel { isSyncingSectionsFromModel = false }

        model.updateProjectSections(id: projectID, sections: new)
        sanitizeActiveFilterTags()
    }

    func handleProjectSectionsChange(_ updated: [Section]) {
        guard updated != sections else { return }
        isSyncingSectionsFromModel = true
        sections = updated
    }

    func handleTagChange() {
        sanitizeActiveFilterTags()
        enforceTimelineAvailability()
    }

    func handleFilterChange(_ newFilters: Set<String>) {
        guard !newFilters.isEmpty else { return }
        if !hasFilterMatch(for: newFilters) {
            showingNoFilterMatchAlert = true
        }
    }

    private var hasAnyTaggedContent: Bool {
        !usedTagsInProject().isEmpty
    }

    private var availableFilterTags: [String] {
        filterableTags()
    }

    @ViewBuilder
    private var toolbarView: some View {
        if showToolbar {
            VStack {
                Button {
                    undoLastProjectChange()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(projectUndoStack.isEmpty ? .gray : .white)
                }
                .disabled(projectUndoStack.isEmpty)
                .help("Undo last change")

                Button {
                    redoLastProjectChange()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(projectRedoStack.isEmpty ? .gray : .white)
                }
                .disabled(projectRedoStack.isEmpty)
                .help("Redo last undone change")

                Spacer()
                    .frame(height: 14)

                Button {
                    splitAtCurrentCaret()
                } label: {
                    Image("row-spacing", bundle: .radixUI)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(splitMode ? .blue : .gray)
                }
                .help("Split text into sections")

                Button {
                    windowMode.toggle()
                } label: {
                    Image(systemName: "rectangle.2.swap")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(windowMode ? .blue : .gray)
                }
                .help("Reorder and view section overview")

                Button {
                    openAllSectionsInWindows()
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor((openingAllSectionWindows || allSectionWindowsVisible) ? .blue : .gray)
                }
                .disabled(openingAllSectionWindows || sections.isEmpty)
                .help(allSectionWindowsVisible ? "Close all section windows" : "Open sections as individual windows")

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
                    openWindow(id: "graveyard-window", value: projectID)
                } label: {
                    Image("crumpled-paper", bundle: .radixUI)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(.gray)
                }
                .help("View deleted sections for this project")

                Button {
                    toggleNotesMode()
                } label: {
                    Image(systemName: "note.text.badge.plus")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(model.noteMode ? .blue : .gray)
                }
                .help(model.noteMode ? "Exit notes mode" : "Notes mode")

                Menu {
                    Button {
                        applyStyle(.bold)
                    } label: {
                        Label("Bold", systemImage: "bold")
                    }

                    Button {
                        applyStyle(.italic)
                    } label: {
                        Label("Italic", systemImage: "italic")
                    }

                    Button {
                        applyStyle(.underline)
                    } label: {
                        Label("Underline", systemImage: "underline")
                    }

                    Button {
                        applyStyle(.strikethrough)
                    } label: {
                        Label("Strikethrough", systemImage: "strikethrough")
                    }

                    Divider()

                    Menu("Text Color") {
                        Button { applyTextColor(.red) } label: {
                            colorPaletteRow(title: "Red", color: .systemRed)
                        }
                        Button { applyTextColor(.blue) } label: {
                            colorPaletteRow(title: "Blue", color: .systemBlue)
                        }
                        Button { applyTextColor(.green) } label: {
                            colorPaletteRow(title: "Green", color: .systemGreen)
                        }
                        Button { applyTextColor(.purple) } label: {
                            colorPaletteRow(title: "Purple", color: .systemPurple)
                        }
                    }

                    Menu("Highlight") {
                        Button { applyTextHighlight(.yellow) } label: {
                            colorPaletteRow(title: "Yellow", color: .systemYellow)
                        }
                        Button { applyTextHighlight(.orange) } label: {
                            colorPaletteRow(title: "Orange", color: .systemOrange)
                        }
                        Button { applyTextHighlight(.green) } label: {
                            colorPaletteRow(title: "Green", color: .systemGreen)
                        }
                        Button { applyTextHighlight(.pink) } label: {
                            colorPaletteRow(title: "Pink", color: .systemPink)
                        }
                        Button { applyTextHighlight(.blue) } label: {
                            colorPaletteRow(title: "Blue", color: .systemBlue)
                        }
                    }

                    Menu("Font Type") {
                        Button { applyTextFontType(.system) } label: {
                            fontTypeRow(title: "System", design: nil)
                        }
                        Button { applyTextFontType(.serif) } label: {
                            fontTypeRow(title: "Serif", design: .serif)
                        }
                        Button { applyTextFontType(.rounded) } label: {
                            fontTypeRow(title: "Rounded", design: .rounded)
                        }
                        Button { applyTextFontType(.monospaced) } label: {
                            fontTypeRow(title: "Monospaced", design: .monospaced)
                        }
                    }

                    Menu("Font Size") {
                        Button {
                            customFontSizeValue = 25
                            showingCustomFontSizeSheet = true
                        } label: {
                            Label("Custom Size…", systemImage: "number")
                        }
                    }

                } label: {
                    Image(systemName: "textformat.alt")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(.gray)
                }
                .help("Text styling options")

                Menu {
                    // Tagging section
                    if !customTagCategories.isEmpty {
                        SwiftUI.Section("Tags") {
                            ForEach(customTagCategories.sorted(), id: \.self) { tag in
                                Button {
                                    toggleTagOnActiveSection(tag)
                                } label: {
                                    HStack {
                                        Text(tag)

                                        let tagState = tagApplicationStateInActiveContext(tag)
                                        if tagState != .none {
                                            tagStateMenuBadge(tagState)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                    
                    // New tag button
                    Button(action: {
                        showingNewTagAlert = true
                    }) {
                        Label("Add New Tag Category", systemImage: "plus")
                    }

                    Divider()

                    Button {
                        showFilteredTimeline.toggle()
                    } label: {
                        HStack {
                            Text("Show as linked timeline")
                            Spacer()
                            if showFilteredTimeline {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .disabled(!hasAnyTaggedContent)
                    
                    Divider()
                    
                    // Filter section
                    if !availableFilterTags.isEmpty {
                        Menu {
                            Button {
                                activeFilterTags.removeAll()
                            } label: {
                                HStack {
                                    Text("Clear Filters")
                                }
                            }
                            .disabled(activeFilterTags.isEmpty)

                            Divider()

                            ForEach(availableFilterTags, id: \.self) { tag in
                                Button {
                                    if activeFilterTags.contains(tag) {
                                        activeFilterTags.remove(tag)
                                    } else {
                                        activeFilterTags.insert(tag)
                                    }
                                } label: {
                                    HStack {
                                        Text(tag)
                                        if activeFilterTags.contains(tag) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                } label: {
                    Image(systemName: "tag.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(
                            hasSelectedTextInActiveSection()
                                ? .orange
                                : (activeFilterTags.isEmpty ? .gray : .blue)
                        )
                        .shadow(
                            color: hasSelectedTextInActiveSection() ? .orange.opacity(0.45) : .clear,
                            radius: hasSelectedTextInActiveSection() ? 4 : 0
                        )
                }
                .help("Tag and filter sections/text")
                .alert("New Tag Category", isPresented: $showingNewTagAlert) {
                    TextField("Tag name", text: $newTagName)
                    Button("Cancel", role: .cancel) {
                        newTagName = ""
                    }
                    Button("Add") {
                        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !customTagCategories.contains(trimmed) {
                            customTagCategories.insert(trimmed)
                        }
                        newTagName = ""
                    }
                } message: {
                    Text("Enter a name for the new tag category")
                }
                
                Menu {
                    Button {
                        sectionWholeDocumentByParagraphs()
                    } label: {
                        Label("Section Document by Paragraphs", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    
                    Divider()

                    Button {
                        rejoinWithNextSection()
                    } label: {
                        Label("Rejoin With Next Section", systemImage: "arrow.trianglehead.merge")
                    }
                    .disabled(activeSectionID == nil || (activeSectionID != nil && (sections.firstIndex(where: { $0.id == activeSectionID! }) ?? (sections.count - 1)) >= sections.count - 1))
                    
                } label: {
                    Image(systemName: "wand.and.sparkles")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .foregroundColor(.gray)
                }
                .help("Extra tools")

                Spacer()
            }
            .frame(width: 60)
            .padding()
            .background(Color(white: 0.95))
            .contextMenu {
                ToolbarContextMenu
            }
        }
    }

    @ViewBuilder
    private var ToolbarContextMenu: some View {
        Button {
            undoLastProjectChange()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(projectUndoStack.isEmpty)

        Button {
            redoLastProjectChange()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(projectRedoStack.isEmpty)

        Divider()

        Button {
            splitAtCurrentCaret()
        } label: {
            Label("Split Text Into Sections", systemImage: "row-spacing")
        }

        Button {
            windowMode.toggle()
        } label: {
            Label("Reorder and View Section Overview", systemImage: "rectangle.2.swap")
        }

        Button {
            openAllSectionsInWindows()
        } label: {
            Label("Open All Sections in Windows", systemImage: "rectangle.grid.2x2")
        }
        .disabled(openingAllSectionWindows || sections.isEmpty)

        Button {
            showingRestitchedManuscript.toggle()
        } label: {
            Label("Restitched Manuscript", systemImage: "doc.text")
        }

        Button {
            openWindow(id: "graveyard-window", value: projectID)
        } label: {
            Label("Deleted Sections", systemImage: "trash")
        }

        Button {
            model.noteMode.toggle()
            if !model.noteMode {
                visibleNoteSectionIDs.removeAll()
                visibleNoteOptionsSectionIDs.removeAll()
                visibleResolvedNoteSectionIDs.removeAll()
                editingNoteKeys.removeAll()
            }
        } label: {
            Label("Notes Mode", systemImage: "note.text.badge.plus")
        }

        Divider()

        Menu {
            Button {
                applyStyle(.bold)
            } label: {
                Label("Bold", systemImage: "bold")
            }

            Button {
                applyStyle(.italic)
            } label: {
                Label("Italic", systemImage: "italic")
            }

            Button {
                applyStyle(.underline)
            } label: {
                Label("Underline", systemImage: "underline")
            }

            Button {
                applyStyle(.strikethrough)
            } label: {
                Label("Strikethrough", systemImage: "strikethrough")
            }

            Divider()

            Menu("Text Color") {
                Button("Red") { applyTextColor(.red) }
                Button("Blue") { applyTextColor(.blue) }
                Button("Green") { applyTextColor(.green) }
                Button("Purple") { applyTextColor(.purple) }
            }

            Menu("Highlight") {
                Button("Yellow") { applyTextHighlight(.yellow) }
                Button("Orange") { applyTextHighlight(.orange) }
                Button("Green") { applyTextHighlight(.green) }
                Button("Pink") { applyTextHighlight(.pink) }
                Button("Blue") { applyTextHighlight(.blue) }
            }

            Menu("Font Type") {
                Button("System") { applyTextFontType(.system) }
                Button("Serif") { applyTextFontType(.serif) }
                Button("Rounded") { applyTextFontType(.rounded) }
                Button("Monospaced") { applyTextFontType(.monospaced) }
            }

            Menu("Font Size") {
                Button("Custom Size…") {
                    customFontSizeValue = 25
                    showingCustomFontSizeSheet = true
                }
            }
        } label: {
            Label("Text Styling", systemImage: "wand.and.sparkles")
        }

        Menu {
            if !customTagCategories.isEmpty {
                SwiftUI.Section("Tags") {
                    ForEach(customTagCategories.sorted(), id: \.self) { tag in
                        Button {
                            toggleTagOnActiveSection(tag)
                        } label: {
                            HStack {
                                Text(tag)

                                let tagState = tagApplicationStateInActiveContext(tag)
                                if tagState != .none {
                                    tagStateMenuBadge(tagState)
                                }
                            }
                        }
                    }
                }
                Divider()
            }

            Button {
                showingNewTagAlert = true
            } label: {
                Label("Add New Tag Category", systemImage: "plus")
            }

            Divider()

            Button {
                showFilteredTimeline.toggle()
            } label: {
                HStack {
                    Text("Show as linked timeline")
                    Spacer()
                    if showFilteredTimeline {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
            .disabled(!hasAnyTaggedContent)

            Divider()

            if !availableFilterTags.isEmpty {
                Button {
                    activeFilterTags.removeAll()
                } label: {
                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(activeFilterTags.isEmpty)

                Divider()

                ForEach(availableFilterTags, id: \.self) { tag in
                    Button {
                        if activeFilterTags.contains(tag) {
                            activeFilterTags.remove(tag)
                        } else {
                            activeFilterTags.insert(tag)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                            if activeFilterTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Tag and Filter", systemImage: "tag.fill")
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
        .contextMenu {
            ToolbarContextMenu
        }
    }

    private func toggleNotesMode() {
        model.noteMode.toggle()
        if !model.noteMode {
            visibleNoteSectionIDs.removeAll()
            visibleNoteOptionsSectionIDs.removeAll()
            visibleResolvedNoteSectionIDs.removeAll()
            editingNoteKeys.removeAll()
        }
    }

    private func selectionEditMenu(suggestedActions: [UIMenuElement]) -> UIMenu {
        let toolMenu = UIMenu(title: "ReViser Tools", children: [
            UIAction(
                title: "Undo",
                image: UIImage(systemName: "arrow.uturn.backward"),
                attributes: projectUndoStack.isEmpty ? [.disabled] : []
            ) { _ in
                undoLastProjectChange()
            },
            UIAction(
                title: "Redo",
                image: UIImage(systemName: "arrow.uturn.forward"),
                attributes: projectRedoStack.isEmpty ? [.disabled] : []
            ) { _ in
                redoLastProjectChange()
            },
            UIAction(
                title: "Split Text",
                image: UIImage(systemName: "row.spacing")
            ) { _ in
                splitAtCurrentCaret()
            },
            UIAction(
                title: "Reorder",
                image: UIImage(systemName: "rectangle.2.swap")
            ) { _ in
                windowMode.toggle()
            },
            UIAction(
                title: "Open All",
                image: UIImage(systemName: "rectangle.grid.2x2"),
                attributes: (openingAllSectionWindows || sections.isEmpty) ? [.disabled] : []
            ) { _ in
                openAllSectionsInWindows()
            },
            UIAction(
                title: showingRestitchedManuscript ? "Close Restitched Manuscript" : "View Restitched Manuscript",
                image: UIImage(systemName: "doc.text")
            ) { _ in
                showingRestitchedManuscript.toggle()
            },
            UIAction(
                title: "Graveyard",
                image: UIImage(systemName: "trash")
            ) { _ in
                openWindow(id: "graveyard-window", value: projectID)
            },
            UIAction(
                title: "Notes",
                image: UIImage(systemName: "note.text.badge.plus")
            ) { _ in
                toggleNotesMode()
            }
        ])

        let stylingMenu = UIMenu(title: "Text Styling", children: [
            UIAction(title: "Bold", image: UIImage(systemName: "bold")) { _ in
                applyStyle(.bold)
            },
            UIAction(title: "Italic", image: UIImage(systemName: "italic")) { _ in
                applyStyle(.italic)
            },
            UIAction(title: "Underline", image: UIImage(systemName: "underline")) { _ in
                applyStyle(.underline)
            },
            UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { _ in
                applyStyle(.strikethrough)
            },
            UIMenu(title: "Text Color", children: [
                UIAction(title: "Red", image: swatchImage(.systemRed)) { _ in applyTextColor(.red) },
                UIAction(title: "Blue", image: swatchImage(.systemBlue)) { _ in applyTextColor(.blue) },
                UIAction(title: "Green", image: swatchImage(.systemGreen)) { _ in applyTextColor(.green) },
                UIAction(title: "Purple", image: swatchImage(.systemPurple)) { _ in applyTextColor(.purple) }
            ]),
            UIMenu(title: "Highlight", children: [
                UIAction(title: "Yellow", image: swatchImage(.systemYellow)) { _ in applyTextHighlight(.yellow) },
                UIAction(title: "Orange", image: swatchImage(.systemOrange)) { _ in applyTextHighlight(.orange) },
                UIAction(title: "Green", image: swatchImage(.systemGreen)) { _ in applyTextHighlight(.green) },
                UIAction(title: "Pink", image: swatchImage(.systemPink)) { _ in applyTextHighlight(.pink) },
                UIAction(title: "Blue", image: swatchImage(.systemBlue)) { _ in applyTextHighlight(.blue) }
            ]),
            UIMenu(title: "Font Size", children: [
                UIAction(title: "Custom Size…", image: UIImage(systemName: "number")) { _ in
                    customFontSizeValue = 25
                    showingCustomFontSizeSheet = true
                }
            ]),
            UIMenu(title: "Font Type", children: [
                UIAction(title: "System", image: UIImage(systemName: "textformat")) { _ in applyTextFontType(.system) },
                UIAction(title: "Serif", image: UIImage(systemName: "textformat.alt")) { _ in applyTextFontType(.serif) },
                UIAction(title: "Rounded", image: UIImage(systemName: "capsule")) { _ in applyTextFontType(.rounded) },
                UIAction(title: "Monospaced", image: UIImage(systemName: "rectangle.grid.1x2")) { _ in applyTextFontType(.monospaced) }
            ])
        ])

        let filterActions = availableFilterTags.map { tag in
            UIAction(
                title: tag,
                state: activeFilterTags.contains(tag) ? .on : .off
            ) { _ in
                if activeFilterTags.contains(tag) {
                    activeFilterTags.remove(tag)
                } else {
                    activeFilterTags.insert(tag)
                }
            }
        }

        let tagActions = customTagCategories.sorted().map { tag in
            UIAction(
                title: tag,
                state: tagApplicationStateInActiveContext(tag) == .none ? .off : .on
            ) { _ in
                toggleTagOnActiveSection(tag)
            }
        }

        let addTagCategoryAction = UIAction(
            title: "New Tag",
            image: UIImage(systemName: "plus")
        ) { _ in
            showingNewTagAlert = true
        }

        let toggleTimelineAction = UIAction(
            title: showFilteredTimeline ? "Hide Linked" : "Show linked",
            image: UIImage(systemName: "tag.fill"),
            attributes: hasAnyTaggedContent ? [] : [.disabled]
        ) { _ in
            showFilteredTimeline.toggle()
        }

        let clearFiltersAction = UIAction(
            title: "Clear Filters",
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            attributes: activeFilterTags.isEmpty ? [.disabled] : []
        ) { _ in
            activeFilterTags.removeAll()
        }

        var tagMenuChildren: [UIMenuElement] = []
        if !tagActions.isEmpty {
            tagMenuChildren.append(UIMenu(title: "Tag Text", children: tagActions))
        }
        tagMenuChildren.append(addTagCategoryAction)
        tagMenuChildren.append(toggleTimelineAction)
        tagMenuChildren.append(UIMenu(title: "Filters", children: [
            clearFiltersAction,
            UIMenu(title: "Active Tags", children: filterActions)
        ]))

        let tagMenu = UIMenu(title: "Tag & Filter", children: tagMenuChildren)

        return UIMenu(children: [toolMenu, stylingMenu, tagMenu] + suggestedActions)
    }

    @ViewBuilder
    private func mainContentView(project: AppModel.Project) -> some View {
        let displayedSections = displayedSectionsForCurrentFilters()

        ZStack(alignment: .topLeading) {
            if shouldShowFilteredTimeline {
                linkedTimelineView()
                    .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                Divider()
                                    .overlay(Color.secondary.opacity(0.18))
                                    .padding(.vertical, 18)
                            }

                            sectionView(section: section, index: originalSectionIndex(for: section.id))
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 28)
                    .padding(.vertical, 40)
                }
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
        .onChange(of: draggedSectionID) { _, newValue in
            if newValue == nil {
                revealedReorderHandleSectionID = nil
            }
        }
    }

    private var shouldShowFilteredTimeline: Bool {
        showFilteredTimeline
    }

    private func displayedSectionsForCurrentFilters() -> [Section] {
        let filteredSections = sections.filter { section in
            let tagsForSection = allTags(for: section.id)
            return activeFilterTags.isEmpty || activeFilterTags.isSubset(of: tagsForSection)
        }

        if !activeFilterTags.isEmpty && filteredSections.isEmpty {
            return sections
        }

        return filteredSections.isEmpty ? sections : filteredSections
    }

    private struct LinkedTimelineFrame: Equatable {
        let id: UUID
        let frame: CGRect
    }

    private struct LinkedTimelineFramePreferenceKey: PreferenceKey {
        static var defaultValue: [LinkedTimelineFrame] = []

        static func reduce(value: inout [LinkedTimelineFrame], nextValue: () -> [LinkedTimelineFrame]) {
            value.append(contentsOf: nextValue())
        }
    }

    private struct LinkedTimelineTextViewFrame: Equatable {
        let id: UUID
        let frame: CGRect
    }

    private struct LinkedTimelineTextViewFramePreferenceKey: PreferenceKey {
        static var defaultValue: [LinkedTimelineTextViewFrame] = []

        static func reduce(value: inout [LinkedTimelineTextViewFrame], nextValue: () -> [LinkedTimelineTextViewFrame]) {
            value.append(contentsOf: nextValue())
        }
    }

    @ViewBuilder
    private func linkedTimelineView() -> some View {
        let displayedSections = displayedSectionsForCurrentFilters()
        let textPointsByTag = linkedTimelineTextPointsByTag(displayedSections: displayedSections)
        let timelineAvailableTags = filterableTags()

        if displayedSections.isEmpty {
            Text("(Empty project)")
                .font(.system(size: 24))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
        } else {
            GeometryReader { proxy in
                let panelWidth: CGFloat = 260
                let contentSpacing: CGFloat = 20
                let canvasWidth = max(proxy.size.width - panelWidth - contentSpacing, 620)
                let columns = timelineColumnCount(for: canvasWidth)
                let gridItems = Array(
                    repeating: GridItem(.flexible(minimum: 360, maximum: 520), spacing: 28),
                    count: columns
                )

                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: contentSpacing) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Linked timeline")
                                        .font(.headline)
                                    Text("Shows section links plus tag-based text links. Use the panel to filter by tags.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(displayedSections.count) sections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.secondary.opacity(0.10))
                                    )
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                            ZStack(alignment: .topLeading) {
                                Canvas { context, _ in
                                    func addSeparatedCurve(
                                        _ path: inout Path,
                                        from startPoint: CGPoint,
                                        to endPoint: CGPoint,
                                        offset: CGFloat
                                    ) {
                                        let sharedControlX = max(startPoint.x, endPoint.x) + offset

                                        path.move(to: startPoint)
                                        path.addCurve(
                                            to: endPoint,
                                            control1: CGPoint(x: sharedControlX, y: startPoint.y),
                                            control2: CGPoint(x: sharedControlX, y: endPoint.y)
                                        )
                                    }

                                    if displayedSections.count > 1 {
                                        for (pairIndex, pair) in zip(displayedSections, displayedSections.dropFirst()).enumerated() {
                                            guard let startFrame = linkedTimelineFrames[pair.0.id],
                                                  let endFrame = linkedTimelineFrames[pair.1.id] else { continue }

                                            let startPoint = CGPoint(x: startFrame.minX, y: startFrame.minY)
                                            let endPoint = CGPoint(x: endFrame.minX, y: endFrame.minY)
                                            let sectionOffset = 26 + CGFloat(pairIndex % 4) * 10

                                            let startSectionTags = sectionLevelTags(for: pair.0.id)
                                            let endSectionTags = sectionLevelTags(for: pair.1.id)
                                            let sharedSectionTags = startSectionTags.intersection(endSectionTags)

                                            let preferredTag =
                                                activeFilterTags.sorted().first(where: { sharedSectionTags.contains($0) }) ??
                                                sharedSectionTags.sorted().first ??
                                                activeFilterTags.sorted().first(where: { startSectionTags.contains($0) || endSectionTags.contains($0) }) ??
                                                startSectionTags.union(endSectionTags).sorted().first

                                            let sectionLinkColor = preferredTag.map { colorForTag($0).opacity(0.65) } ?? Color.blue.opacity(0.35)

                                            var sectionPath = Path()
                                            addSeparatedCurve(&sectionPath, from: startPoint, to: endPoint, offset: sectionOffset)

                                            context.stroke(
                                                sectionPath,
                                                with: .color(sectionLinkColor),
                                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 6])
                                            )
                                        }
                                    }

                                    let orderedTags = textPointsByTag.keys.sorted()

                                    for (tagIndex, tag) in orderedTags.enumerated() {
                                        guard let points = textPointsByTag[tag], points.count > 1 else { continue }

                                        let textOffset = 18 + CGFloat(tagIndex % 6) * 8
                                        var textPath = Path()

                                        for pair in zip(points, points.dropFirst()) {
                                            let startPoint = pair.0
                                            let endPoint = pair.1

                                            addSeparatedCurve(&textPath, from: startPoint, to: endPoint, offset: textOffset)
                                        }

                                        context.stroke(
                                            textPath,
                                            with: .color(colorForTag(tag).opacity(0.80)),
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                        )
                                    }
                                }
                                .allowsHitTesting(false)

                                LazyVGrid(columns: gridItems, alignment: .leading, spacing: 28) {
                                    ForEach(displayedSections, id: \.id) { section in
                                        timelineCardView(section: section)
                                            .background(
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: LinkedTimelineFramePreferenceKey.self,
                                                        value: [LinkedTimelineFrame(id: section.id, frame: proxy.frame(in: .named("linkedTimelineCanvas")))]
                                                    )
                                                }
                                            )
                                    }
                                }
                            }
                            .coordinateSpace(name: "linkedTimelineCanvas")
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(.secondarySystemBackground), Color(.secondarySystemBackground).opacity(0.96)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .frame(width: canvasWidth, alignment: .leading)
                        .padding(.leading, 24)
                        .padding(.bottom, 24)

                        timelineTagFilterPanel(availableTags: timelineAvailableTags)
                            .frame(width: panelWidth)
                            .padding(.trailing, 24)
                            .padding(.top, 12)
                    }
                }
                .onPreferenceChange(LinkedTimelineFramePreferenceKey.self) { frames in
                    linkedTimelineFrames = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.frame) })
                }
                .onPreferenceChange(LinkedTimelineTextViewFramePreferenceKey.self) { frames in
                    linkedTimelineTextViewFrames = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.frame) })
                }
            }
        }
    }

    private func linkedTimelineTextPointsByTag(displayedSections: [Section]) -> [String: [CGPoint]] {
        var pointsByTag: [String: [(Int, CGPoint)]] = [:]

        for (sectionIndex, section) in displayedSections.enumerated() {
            guard let textFrame = linkedTimelineTextViewFrames[section.id],
                  let snippetPoints = linkedTimelineSnippetPoints[section.id],
                  let taggedSnippets = taggedTextBySection[section.id] else { continue }

            for (snippet, tags) in taggedSnippets {
                guard let points = snippetPoints[snippet], !points.isEmpty else { continue }

                for point in points {
                    let canvasPoint = CGPoint(x: textFrame.minX + point.x, y: textFrame.minY + point.y)
                    for tag in tags {
                        if !activeFilterTags.isEmpty && !activeFilterTags.contains(tag) {
                            continue
                        }
                        pointsByTag[tag, default: []].append((sectionIndex, canvasPoint))
                    }
                }
            }
        }

        return pointsByTag.mapValues { entries in
            entries
                .sorted { lhs, rhs in
                    if lhs.0 == rhs.0 {
                        return lhs.1.y < rhs.1.y
                    }
                    return lhs.0 < rhs.0
                }
                .map { $0.1 }
        }
    }

    private func colorForTag(_ tag: String) -> Color {
        let scalarSum = tag.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(scalarSum % 360) / 360.0
        return Color(hue: hue, saturation: 0.78, brightness: 0.95)
    }

    @ViewBuilder
    private func timelineTagFilterPanel(availableTags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline filters")
                .font(.headline)

            Text("Select tags to focus the section set and tag links.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if availableTags.isEmpty {
                Text("No tags available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                Button("Clear tag filters") {
                    activeFilterTags.removeAll()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(activeFilterTags.isEmpty)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                if activeFilterTags.contains(tag) {
                                    activeFilterTags.remove(tag)
                                } else {
                                    activeFilterTags.insert(tag)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(colorForTag(tag))
                                        .frame(width: 10, height: 10)

                                    Text(tag)
                                        .font(.subheadline)
                                        .lineLimit(1)

                                    Spacer()

                                    if activeFilterTags.contains(tag) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(activeFilterTags.contains(tag) ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func timelineColumnCount(for width: CGFloat) -> Int {
        let availableWidth = max(width - 72, 360)
        let preferredColumns = Int(availableWidth / 460)
        return min(max(preferredColumns, 1), 3)
    }

    private func originalSectionIndex(for sectionID: UUID) -> Int {
        sections.firstIndex(where: { $0.id == sectionID }) ?? 0
    }

    @ViewBuilder
    private func timelineCardView(section: Section) -> some View {
        let sectionNumber = originalSectionIndex(for: section.id) + 1
        let sectionLevelTagSet = sectionLevelTags(for: section.id)
        let textLevelTagSet = textLevelTags(for: section.id)
        let tags = sectionLevelTagSet.union(textLevelTagSet).sorted()

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Section \(sectionNumber)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(activeFilterTags.isEmpty ? "All content" : "Filtered match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(activeFilterTags.isEmpty ? Color.secondary.opacity(0.45) : Color.orange.opacity(0.85))
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)
            }

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            let isSectionTag = sectionLevelTagSet.contains(tag)
                            let isTextTag = textLevelTagSet.contains(tag)
                            let foregroundColor: Color = {
                                if isSectionTag && isTextTag { return .orange }
                                if isSectionTag { return .blue }
                                if isTextTag { return .orange }
                                return .secondary
                            }()

                            let backgroundColor: Color = {
                                if isSectionTag && isTextTag { return Color.blue.opacity(0.20) }
                                if isSectionTag { return Color.blue.opacity(0.14) }
                                if isTextTag { return Color.orange.opacity(0.14) }
                                return Color.secondary.opacity(0.10)
                            }()

                            Text(tag)
                                .font(.caption2)
                                .foregroundStyle(foregroundColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(backgroundColor)
                                )
                        }
                    }
                }
            }

            sectionTimelineView(section: section)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(activeFilterTags.isEmpty ? Color.secondary.opacity(0.35) : Color.orange.opacity(0.55))
                .frame(width: 4)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private func sectionTimelineView(section: Section) -> some View {
        let sectionLevelTags = sectionLevelTags(for: section.id)
        let textLevelTags = textLevelTags(for: section.id)
        let textTaggedSnippets = Set(taggedTextBySection[section.id]?.keys.map { $0 } ?? [])
        let hasSectionTags = !sectionLevelTags.isEmpty
        let hasTextTags = !textLevelTags.isEmpty
        let hasTags = hasSectionTags || hasTextTags
        let tooltipText = [
            hasSectionTags ? "Section tags: \(sectionLevelTags.sorted().joined(separator: ", "))" : nil,
            hasTextTags ? "Text tags: \(textLevelTags.sorted().joined(separator: ", "))" : nil
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        TextKitView(
            text: binding(for: section),
            highlightedSnippets: textTaggedSnippets,
            textColors: section.colors,
            textHighlights: section.highlights,
            textFontTypes: section.fontTypes,
            textFontSizes: section.fontSizes,
            splitMode: splitMode,
            snappedY: $snappedY,
            onSplit: { y in
                splitSection(id: section.id, y: y)
            },
            onAttach: { view in
                textViews[section.id] = view
            },
            onSelectionChange: { caret, selectionLength in
                activeSectionID = section.id
                caretIndexBySection[section.id] = caret
                selectedLengthBySection[section.id] = selectionLength
            },
            calculatedHeight: Binding(
                get: { sectionHeights[section.id] ?? 100 },
                set: { sectionHeights[section.id] = $0 }
            ),
            onHighlightedSnippetAnchorsChange: { snippetPoints in
                linkedTimelineSnippetPoints[section.id] = snippetPoints
            },
            selectionMenuBuilder: { suggestedActions in
                selectionEditMenu(suggestedActions: suggestedActions)
            }
        )
        .multilineTextAlignment(.leading)
        .frame(height: sectionHeights[section.id] ?? 100)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LinkedTimelineTextViewFramePreferenceKey.self,
                    value: [LinkedTimelineTextViewFrame(id: section.id, frame: proxy.frame(in: .named("linkedTimelineCanvas")))]
                )
            }
        )
        .overlay(alignment: .topLeading) {
            if hasTags {
                Button {
                    presentTagActions(for: section.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        if hasSectionTags {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                        }

                        if hasTextTags {
                            Image(systemName: "text.badge.checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help(tooltipText)
            }
        }

        if model.noteMode {
            sectionNotesView(sectionID: section.id)
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

    private func restitchedManuscriptAttributedString() -> AttributedString {
        let renderedSections = sections.isEmpty ? [Section(id: UUID(), text: "(Empty project)")] : sections
        let combined = NSMutableAttributedString()

        for (index, section) in renderedSections.enumerated() {
            let sectionAttributed = NSMutableAttributedString(string: section.text)
            let fullRange = NSRange(location: 0, length: (section.text as NSString).length)
            sectionAttributed.addAttributes([
                .font: UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ], range: fullRange)

            applyRestitchedInlineStyles(
                to: sectionAttributed,
                text: section.text,
                colors: section.colors,
                highlights: section.highlights,
                fontTypes: section.fontTypes,
                fontSizes: section.fontSizes,
                boldStyles: section.boldStyles,
                italicStyles: section.italicStyles,
                underlineStyles: section.underlineStyles,
                strikethroughStyles: section.strikethroughStyles
            )

            combined.append(sectionAttributed)

            if index < renderedSections.count - 1 {
                combined.append(NSAttributedString(string: "\n"))
            }
        }

        if combined.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttributedString("(Empty project)")
        }

        return AttributedString(combined)
    }

    private func applyRestitchedInlineStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        colors: [TextStyleRange],
        highlights: [TextStyleRange],
        fontTypes: [TextStyleRange],
        fontSizes: [TextStyleRange],
        boldStyles: [TextStyleRange],
        italicStyles: [TextStyleRange],
        underlineStyles: [TextStyleRange],
        strikethroughStyles: [TextStyleRange]
    ) {
        applyRestitchedColorStyles(to: attributed, text: text, colors: colors)
        applyRestitchedHighlightStyles(to: attributed, text: text, highlights: highlights)
        applyRestitchedFontTypeStyles(to: attributed, text: text, fontTypes: fontTypes)
        applyRestitchedFontSizeStyles(to: attributed, text: text, fontSizes: fontSizes)
        applyRestitchedFontTraitStyles(to: attributed, text: text, ranges: boldStyles, trait: .traitBold)
        applyRestitchedFontTraitStyles(to: attributed, text: text, ranges: italicStyles, trait: .traitItalic)
        

        let textLength = (text as NSString).length

        for range in underlineStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }

        for range in strikethroughStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyRestitchedColorStyles(to attributed: NSMutableAttributedString, text: String, colors: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in colors {
            guard let style = ProjectDetailView.TextColorStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.foregroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyRestitchedHighlightStyles(to attributed: NSMutableAttributedString, text: String, highlights: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in highlights {
            guard let style = ProjectDetailView.TextHighlightStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.backgroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyRestitchedFontTypeStyles(to attributed: NSMutableAttributedString, text: String, fontTypes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontTypes {
            guard let style = ProjectDetailView.TextFontTypeStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            let font: UIFont
            if let design = style.uiKitDesign,
               let designedDescriptor = existingFont.fontDescriptor.withDesign(design) {
                font = UIFont(descriptor: designedDescriptor, size: existingFont.pointSize)
            } else {
                font = UIFont.systemFont(ofSize: existingFont.pointSize)
            }

            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private func applyRestitchedFontSizeStyles(to attributed: NSMutableAttributedString, text: String, fontSizes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontSizes {
            guard let pointSize = ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            attributed.addAttribute(.font, value: existingFont.withSize(pointSize), range: nsRange)
        }
    }

    private func applyRestitchedFontTraitStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        ranges: [TextStyleRange],
        trait: UIFontDescriptor.SymbolicTraits
    ) {
        let textLength = (text as NSString).length

        for range in ranges {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 24)
            let combinedTraits = existingFont.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(combinedTraits) {
                let font = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                attributed.addAttribute(.font, value: font, range: nsRange)
            }
        }
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
                        restitchedDocxDocument = RestitchedManuscriptDocxDocument(sections: sections)
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
                let manuscriptAttributedText = restitchedManuscriptAttributedString()
                if manuscriptAttributedText.characters.isEmpty {
                    Text("(Empty project)")
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                } else {
                    Text(manuscriptAttributedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    func sectionView(section: Section, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            let sectionLevelTags = sectionLevelTags(for: section.id)
            let textLevelTags = textLevelTags(for: section.id)
            let textTaggedSnippets = Set(taggedTextBySection[section.id]?.keys.map { $0 } ?? [])
            let hasSectionTags = !sectionLevelTags.isEmpty
            let hasTextTags = !textLevelTags.isEmpty
            let hasTags = hasSectionTags || hasTextTags
            let tooltipText = [
                hasSectionTags ? "Section tags: \(sectionLevelTags.sorted().joined(separator: ", "))" : nil,
                hasTextTags ? "Text tags: \(textLevelTags.sorted().joined(separator: ", "))" : nil
            ]
                .compactMap { $0 }
                .joined(separator: "\n")

            VStack(alignment: .center, spacing: 8) {
                reorderHandleView(for: section)

                if hasTags {
                    Button {
                        presentTagActions(for: section.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if hasSectionTags {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }

                            if hasTextTags {
                                Image(systemName: "text.badge.checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(tooltipText)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TextKitView(
                    text: binding(for: section),
                    highlightedSnippets: textTaggedSnippets,
                    textColors: section.colors,
                    textHighlights: section.highlights,
                    textFontTypes: section.fontTypes,
                    textFontSizes: section.fontSizes,
                    textBoldStyles: section.boldStyles,
                    textItalicStyles: section.italicStyles,
                    textUnderlineStyles: section.underlineStyles,
                    textStrikethroughStyles: section.strikethroughStyles,
                    splitMode: splitMode,
                    snappedY: $snappedY,
                    onSplit: { y in
                        splitSection(id: section.id, y: y)
                    },
                    onAttach: { view in
                        textViews[section.id] = view
                    },
                    onSelectionChange: { caret, selectionLength in
                        activeSectionID = section.id
                        caretIndexBySection[section.id] = caret
                        selectedLengthBySection[section.id] = selectionLength
                    },
                    calculatedHeight: Binding(
                        get: { sectionHeights[section.id] ?? 100 },
                        set: { sectionHeights[section.id] = $0 }
                    ),
                    selectionMenuBuilder: { suggestedActions in
                        selectionEditMenu(suggestedActions: suggestedActions)
                    }
                )
                .multilineTextAlignment(.leading)
                .frame(height: sectionHeights[section.id] ?? 100)
                .frame(maxWidth: .infinity)

                if model.noteMode {
                    sectionNotesView(sectionID: section.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                if revealedReorderHandleSectionID == section.id {
                    revealedReorderHandleSectionID = nil
                }
            })

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
                            pendingSectionDeletion = .section(sectionID: section.id)
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

    @ViewBuilder
    private func reorderHandleView(for section: Section) -> some View {
        if revealedReorderHandleSectionID == section.id {
            Image("drag-handle-dots-2", bundle: .radixUI)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onDrag {
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
                .help("Drag to reorder")
        } else {
            Button {
                revealedReorderHandleSectionID = section.id
            } label: {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 10, height: 10)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("Show drag handle")
        }
    }
    
    @ViewBuilder
    private func sectionNotesView(sectionID: UUID) -> some View {
        let sectionIndex = sections.firstIndex(where: { $0.id == sectionID })
        let notes = sectionIndex.map { sections[$0].notes } ?? []
        let resolvedNotes = sectionIndex.map { sections[$0].resolvedNotes } ?? []

        VStack(alignment: .leading, spacing: 8) {
            if notes.isEmpty {
                Text("No notes yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(notes.indices), id: \.self) { noteIndex in
                    let noteKey = "\(sectionID.uuidString)-\(noteIndex)"
                    let resolveKey = "\(sectionID.uuidString)-\(noteIndex)"
                    let isEditingNote = editingNoteKeys.contains(noteKey)

                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if isEditingNote, let sectionIndex {
                            let currentIndex = sectionIndex
                            let binding: Binding<String> = Binding(
                                get: {
                                    guard sections.indices.contains(currentIndex),
                                          sections[currentIndex].notes.indices.contains(noteIndex) else { return "" }
                                    return sections[currentIndex].notes[noteIndex]
                                },
                                set: { newValue in
                                    guard sections.indices.contains(currentIndex),
                                          sections[currentIndex].notes.indices.contains(noteIndex) else { return }
                                    sections[currentIndex].notes[noteIndex] = newValue
                                }
                            )

                            TextField("Edit note", text: binding)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)

                            Button {
                                editingNoteKeys.remove(noteKey)
                            } label: {
                                Text("Save")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Save edit")
                        } else {
                            Text(notes[noteIndex])
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 6) {
                                if revealedResolveNoteKey == resolveKey {
                                    Button {
                                        editingNoteKeys.insert(noteKey)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 44, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(Color.secondary.opacity(0.08))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Edit note")

                                    Button {
                                        resolveNote(sectionID: sectionID, noteIndex: noteIndex)
                                        revealedResolveNoteKey = nil
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
                                    if revealedResolveNoteKey == resolveKey {
                                        revealedResolveNoteKey = nil
                                    } else {
                                        revealedResolveNoteKey = resolveKey
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.secondary.opacity(0.18))
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(revealedResolveNoteKey == resolveKey ? "Hide note actions" : "Show note actions")
                            }
                            .frame(width: 120, alignment: .trailing)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditingNote {
                            if revealedResolveNoteKey == resolveKey {
                                revealedResolveNoteKey = nil
                            } else {
                                revealedResolveNoteKey = resolveKey
                            }
                        }
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

                    Button {
                        pendingNoteDeletion = .clearAll(sectionID: sectionID)
                    } label: {
                        Label("Clear All", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !(sections.first(where: { $0.id == sectionID })?.notes.isEmpty == false ||
                          sections.first(where: { $0.id == sectionID })?.resolvedNotes.isEmpty == false)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if visibleResolvedNoteSectionIDs.contains(sectionID) {
                if resolvedNotes.isEmpty {
                    Text("No resolved notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(resolvedNotes.enumerated()), id: \.offset) { resolvedIndex, note in
                        let resolvedNoteKey = "resolved-\(sectionID.uuidString)-\(resolvedIndex)"

                        HStack(alignment: .top, spacing: 8) {
                            Text("• \(note)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if revealedResolveNoteKey == resolvedNoteKey {
                                Button {
                                    pendingNoteDeletion = .resolvedNote(sectionID: sectionID, resolvedIndex: resolvedIndex)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red.opacity(0.10))
                                            .frame(width: 24, height: 24)

                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.red)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Delete resolved note")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if revealedResolveNoteKey == resolvedNoteKey {
                                revealedResolveNoteKey = nil
                            } else {
                                revealedResolveNoteKey = resolvedNoteKey
                            }
                        }
                    }
                }
            }

            if visibleNoteSectionIDs.contains(sectionID) {
                HStack(spacing: 8) {
                    let draftBinding: Binding<String> = Binding(
                        get: { noteDraftBySection[sectionID] ?? "" },
                        set: { noteDraftBySection[sectionID] = $0 }
                    )
                    TextField("Add a note to this section", text: draftBinding)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addNote(to: sectionID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((noteDraftBySection[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
        let sourceSection = sections[index]
        let nsText = text as NSString
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

        let firstRange = NSRange(location: 0, length: charIndex)
        let first = nsText.substring(with: firstRange)

        var secondStart = charIndex
        if secondStart < nsText.length, nsText.substring(with: NSRange(location: secondStart, length: 1)) == "\n" {
            secondStart += 1
        }

        let secondRange = NSRange(location: secondStart, length: nsText.length - secondStart)
        let second = nsText.substring(with: secondRange)

        let originalHeight = sectionHeights[id] ?? textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        let firstID = UUID()
        let secondID = UUID()

        sections.remove(at: index)

        if !first.isEmpty {
            sections.insert(styledSection(from: sourceSection, text: first, sourceRange: firstRange, id: firstID), at: index)
        }

        if !second.isEmpty {
            sections.insert(styledSection(from: sourceSection, text: second, sourceRange: secondRange, id: secondID), at: index + (first.isEmpty ? 0 : 1))
        }

        seedSplitHeights(
            originalHeight: originalHeight,
            firstID: first.isEmpty ? nil : firstID,
            firstLength: first.count,
            middleID: nil,
            middleLength: 0,
            secondID: second.isEmpty ? nil : secondID,
            secondLength: second.count
        )
        sectionHeights[id] = nil
    }

    func splitAtCurrentCaret() {
        guard let id = activeSectionID,
              let index = sections.firstIndex(where: { $0.id == id }),
              let textView = textViews[id] else { return }

        let text = sections[index].text
        let sourceSection = sections[index]
        let nsText = text as NSString
        let selectedRange = clampSelectionRange(textView.selectedRange, textLength: nsText.length)

        let first = nsText.substring(to: selectedRange.location)
        let middle = selectedRange.length > 0 ? nsText.substring(with: selectedRange) : ""
        let second = nsText.substring(from: selectedRange.location + selectedRange.length)

        let originalHeight = sectionHeights[id] ?? textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height

        sections.remove(at: index)

        textViews[id] = nil
        sectionHeights[id] = nil
        caretIndexBySection[id] = nil
        visibleNoteOptionsSectionIDs.remove(id)
        visibleNoteSectionIDs.remove(id)
        visibleResolvedNoteSectionIDs.remove(id)
        noteDraftBySection[id] = nil
        editingNoteKeys = editingNoteKeys.filter { !$0.hasPrefix("\(id.uuidString)-") }

        var insertedSectionIDs: [UUID] = []
        let firstSectionID = first.isEmpty ? nil : UUID()
        let middleSectionID = middle.isEmpty ? nil : UUID()
        let secondSectionID = second.isEmpty ? nil : UUID()

        if let firstSectionID {
            sections.insert(styledSection(from: sourceSection, text: first, sourceRange: NSRange(location: 0, length: selectedRange.location), id: firstSectionID), at: index)
            insertedSectionIDs.append(firstSectionID)
        }

        if let middleSectionID {
            sections.insert(styledSection(from: sourceSection, text: middle, sourceRange: selectedRange, id: middleSectionID), at: index + insertedSectionIDs.count)
            insertedSectionIDs.append(middleSectionID)
        }

        if let secondSectionID {
            sections.insert(styledSection(from: sourceSection, text: second, sourceRange: NSRange(location: selectedRange.location + selectedRange.length, length: nsText.length - (selectedRange.location + selectedRange.length)), id: secondSectionID), at: index + insertedSectionIDs.count)
            insertedSectionIDs.append(secondSectionID)
        }

        seedSplitHeights(
            originalHeight: originalHeight,
            firstID: firstSectionID,
            firstLength: first.count,
            middleID: middleSectionID,
            middleLength: middle.count,
            secondID: secondSectionID,
            secondLength: second.count
        )

        if let newActiveSectionID = insertedSectionIDs.first(where: { sectionID in
            sections.first(where: { $0.id == sectionID })?.text == middle
        }) ?? insertedSectionIDs.first {
            activeSectionID = newActiveSectionID
        } else {
            activeSectionID = sections.first?.id
        }
    }

    private func seedSplitHeights(
        originalHeight: CGFloat,
        firstID: UUID?,
        firstLength: Int,
        middleID: UUID?,
        middleLength: Int,
        secondID: UUID?,
        secondLength: Int
    ) {
        guard originalHeight > 0 else { return }
        let totalLength = firstLength + middleLength + secondLength
        guard totalLength > 0 else { return }

        let pieces: [(UUID?, Int)] = [
            (firstID, firstLength),
            (middleID, middleLength),
            (secondID, secondLength)
        ].filter { $0.0 != nil }

        let presentLength = pieces.reduce(0) { $0 + $1.1 }
        guard presentLength > 0 else { return }

        for (id, length) in pieces {
            guard let id else { continue }
            let fraction = CGFloat(length) / CGFloat(presentLength)
            sectionHeights[id] = max(originalHeight * fraction, 60)
        }
    }

    private func clampSelectionRange(_ range: NSRange, textLength: Int) -> NSRange {
        let clampedLocation = min(max(range.location, 0), textLength)
        let clampedLength = min(max(range.length, 0), textLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    func sectionWholeDocumentByParagraphs() {
        guard !sections.isEmpty else { return }

        let currentSections = sections
        var rebuiltSections: [Section] = []

        for section in currentSections {
            let paragraphSlices = paragraphSlices(in: section.text)

            if paragraphSlices.isEmpty {
                rebuiltSections.append(Section(id: UUID(), text: ""))
                continue
            }

            for (paragraphIndex, paragraphSlice) in paragraphSlices.enumerated() {
                let isPrimaryParagraph = paragraphIndex == 0
                let paragraphSection = styledSection(
                    from: section,
                    text: paragraphSlice.text,
                    sourceRange: paragraphSlice.range,
                    id: UUID()
                )

                rebuiltSections.append(
                    Section(
                        id: paragraphSection.id,
                        text: paragraphSection.text,
                        notes: isPrimaryParagraph ? paragraphSection.notes : [],
                        resolvedNotes: isPrimaryParagraph ? paragraphSection.resolvedNotes : [],
                        colors: paragraphSection.colors,
                        highlights: paragraphSection.highlights,
                        fontTypes: paragraphSection.fontTypes,
                        fontSizes: paragraphSection.fontSizes,
                        boldStyles: paragraphSection.boldStyles,
                        italicStyles: paragraphSection.italicStyles,
                        underlineStyles: paragraphSection.underlineStyles,
                        strikethroughStyles: paragraphSection.strikethroughStyles
                    )
                )
            }
        }

        sections = rebuiltSections.isEmpty ? [Section(id: UUID(), text: "")] : rebuiltSections

        if let firstSectionID = sections.first?.id {
            activeSectionID = firstSectionID
        }

        textViews.removeAll()
        sectionHeights.removeAll()
        caretIndexBySection.removeAll()
        selectedLengthBySection.removeAll()
        visibleActionSectionIDs.removeAll()
        visibleNoteSectionIDs.removeAll()
        visibleNoteOptionsSectionIDs.removeAll()
        visibleResolvedNoteSectionIDs.removeAll()
        revealedResolveNoteKey = nil
        noteDraftBySection.removeAll()
        editingNoteKeys.removeAll()
        sectionTags.removeAll()
        taggedTextBySection.removeAll()
        showFilteredTimeline = false
        linkedTimelineFrames.removeAll()
        linkedTimelineTextViewFrames.removeAll()
        linkedTimelineSnippetPoints.removeAll()
    }
    
    private func offsetRanges(_ ranges: [TextStyleRange], by delta: Int) -> [TextStyleRange] {
        guard delta != 0 else { return ranges }
        return ranges.map { TextStyleRange(location: $0.location + delta, length: $0.length, style: $0.style) }
    }

    private func clippedRanges(_ ranges: [TextStyleRange], in sourceRange: NSRange) -> [TextStyleRange] {
        let sourceStart = sourceRange.location
        let sourceEnd = sourceRange.location + sourceRange.length

        return ranges.compactMap { range in
            let rangeStart = range.location
            let rangeEnd = range.location + range.length
            let clippedStart = max(rangeStart, sourceStart)
            let clippedEnd = min(rangeEnd, sourceEnd)

            guard clippedEnd > clippedStart else { return nil }

            return TextStyleRange(
                location: clippedStart - sourceStart,
                length: clippedEnd - clippedStart,
                style: range.style
            )
        }
    }

    private func styledSection(from section: Section, text: String, sourceRange: NSRange, id: UUID) -> Section {
        Section(
            id: id,
            text: text,
            notes: sourceRange.location == 0 ? section.notes : [],
            resolvedNotes: sourceRange.location == 0 ? section.resolvedNotes : [],
            colors: clippedRanges(section.colors, in: sourceRange),
            highlights: clippedRanges(section.highlights, in: sourceRange),
            fontTypes: clippedRanges(section.fontTypes, in: sourceRange),
            fontSizes: clippedRanges(section.fontSizes, in: sourceRange),
            boldStyles: clippedRanges(section.boldStyles, in: sourceRange),
            italicStyles: clippedRanges(section.italicStyles, in: sourceRange),
            underlineStyles: clippedRanges(section.underlineStyles, in: sourceRange),
            strikethroughStyles: clippedRanges(section.strikethroughStyles, in: sourceRange)
        )
    }

    func rejoinWithNextSection() {
        guard let currentID = activeSectionID,
              let currentIndex = sections.firstIndex(where: { $0.id == currentID }),
              currentIndex + 1 < sections.count else { return }

        // Capture undo before mutation
        pushUndoSnapshot(currentSnapshot())

        var current = sections[currentIndex]
        let next = sections[currentIndex + 1]

        // Prepare text merge
        let currentText = current.text
        let needsSeparator = !(currentText.hasSuffix("\n") || next.text.hasPrefix("\n")) && !currentText.isEmpty && !next.text.isEmpty
        let separator = needsSeparator ? "\n" : ""
        let joinOffset = (currentText as NSString).length + (separator as NSString).length

        // Merge text
        current.text = current.text + separator + next.text

        // Merge notes and resolved notes
        current.notes.append(contentsOf: next.notes)
        current.resolvedNotes.append(contentsOf: next.resolvedNotes)

        // Merge styled ranges (offset next ranges by joinOffset)
        current.colors.append(contentsOf: offsetRanges(next.colors, by: joinOffset))
        current.highlights.append(contentsOf: offsetRanges(next.highlights, by: joinOffset))
        current.fontTypes.append(contentsOf: offsetRanges(next.fontTypes, by: joinOffset))
        current.fontSizes.append(contentsOf: offsetRanges(next.fontSizes, by: joinOffset))
        current.boldStyles.append(contentsOf: offsetRanges(next.boldStyles, by: joinOffset))
        current.italicStyles.append(contentsOf: offsetRanges(next.italicStyles, by: joinOffset))
        current.underlineStyles.append(contentsOf: offsetRanges(next.underlineStyles, by: joinOffset))
        current.strikethroughStyles.append(contentsOf: offsetRanges(next.strikethroughStyles, by: joinOffset))

        // Apply merged current back into sections and remove next
        sections[currentIndex] = current
        let removedID = sections[currentIndex + 1].id
        sections.remove(at: currentIndex + 1)

        // Merge section-level tags
        if let nextSectionTags = sectionTags[removedID] {
            if sectionTags[currentID] == nil { sectionTags[currentID] = [] }
            sectionTags[currentID]?.formUnion(nextSectionTags)
            sectionTags[removedID] = nil
        }

        // Merge text-level tags (tagged snippets)
        if let nextSnippets = taggedTextBySection[removedID] {
            if taggedTextBySection[currentID] == nil { taggedTextBySection[currentID] = [:] }
            for (snippet, tags) in nextSnippets {
                if var existing = taggedTextBySection[currentID]?[snippet] {
                    existing.formUnion(tags)
                    taggedTextBySection[currentID]?[snippet] = existing
                } else {
                    taggedTextBySection[currentID]?[snippet] = tags
                }
            }
            taggedTextBySection[removedID] = nil
        }

        // Cleanup view/state caches for removed section
        textViews[removedID] = nil
        sectionHeights[removedID] = nil
        caretIndexBySection[removedID] = nil
        selectedLengthBySection[removedID] = nil
        visibleActionSectionIDs.remove(removedID)
        visibleNoteOptionsSectionIDs.remove(removedID)
        visibleNoteSectionIDs.remove(removedID)
        visibleResolvedNoteSectionIDs.remove(removedID)
        noteDraftBySection[removedID] = nil

        // Linked timeline caches
        linkedTimelineFrames[removedID] = nil
        linkedTimelineTextViewFrames[removedID] = nil
        linkedTimelineSnippetPoints[removedID] = nil

        // If a resolve key was showing for the removed section, clear it
        if let key = revealedResolveNoteKey, key.hasPrefix("\(removedID.uuidString)-") {
            revealedResolveNoteKey = nil
        }

        // Keep focus on the merged section
        activeSectionID = currentID
    }

    private func paragraphs(in text: String) -> [String] {
        let nsText = text as NSString
        var paragraphs: [String] = []
        var currentParagraph = ""
        var separatorRun = ""
        var hasParagraphContent = false
        var index = 0

        while index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let lineText = nsText.substring(with: lineRange)

            if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if hasParagraphContent {
                    separatorRun += lineText
                } else {
                    separatorRun += lineText
                }
            } else {
                if !hasParagraphContent {
                    currentParagraph = separatorRun + lineText
                    separatorRun = ""
                    hasParagraphContent = true
                } else if !separatorRun.isEmpty {
                    paragraphs.append(currentParagraph + separatorRun)
                    currentParagraph = lineText
                    separatorRun = ""
                } else {
                    currentParagraph += lineText
                }
            }

            index = lineRange.location + lineRange.length
        }

        if hasParagraphContent {
            paragraphs.append(currentParagraph + separatorRun)
        } else if !separatorRun.isEmpty {
            paragraphs.append(separatorRun)
        }

        return paragraphs
    }

    private func paragraphSlices(in text: String) -> [(text: String, range: NSRange)] {
        let nsText = text as NSString
        var slices: [(text: String, range: NSRange)] = []
        var currentParagraph = ""
        var separatorRun = ""
        var separatorStart: Int?
        var paragraphStart: Int?
        var hasParagraphContent = false
        var index = 0

        while index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let lineText = nsText.substring(with: lineRange)
            let isBlank = lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isBlank {
                if !hasParagraphContent && separatorStart == nil {
                    separatorStart = lineRange.location
                }
                separatorRun += lineText
            } else {
                if !hasParagraphContent {
                    paragraphStart = separatorStart ?? lineRange.location
                    currentParagraph = separatorRun + lineText
                    separatorRun = ""
                    separatorStart = nil
                    hasParagraphContent = true
                } else if !separatorRun.isEmpty {
                    if let start = paragraphStart {
                        let length = (currentParagraph as NSString).length + (separatorRun as NSString).length
                        slices.append((currentParagraph + separatorRun, NSRange(location: start, length: length)))
                    }
                    paragraphStart = lineRange.location
                    currentParagraph = lineText
                    separatorRun = ""
                    separatorStart = nil
                } else {
                    currentParagraph += lineText
                }
            }

            index = lineRange.location + lineRange.length
        }

        if hasParagraphContent {
            if let start = paragraphStart {
                let length = (currentParagraph as NSString).length + (separatorRun as NSString).length
                slices.append((currentParagraph + separatorRun, NSRange(location: start, length: length)))
            }
        } else if !separatorRun.isEmpty {
            let start = separatorStart ?? 0
            slices.append((separatorRun, NSRange(location: start, length: (separatorRun as NSString).length)))
        }

        return slices
    }

    func undoLastProjectChange() {
        guard let previousSnapshot = projectUndoStack.popLast() else { return }

        pushRedoSnapshot(currentSnapshot())

        isApplyingUndo = true
        applySnapshot(previousSnapshot)

        let validIDs = Set(sections.map(\.id))
        if let activeSectionID, !validIDs.contains(activeSectionID) {
            self.activeSectionID = sections.first?.id
        }

        textViews = textViews.filter { validIDs.contains($0.key) }
        sectionHeights = sectionHeights.filter { validIDs.contains($0.key) }
        caretIndexBySection = caretIndexBySection.filter { validIDs.contains($0.key) }
        visibleActionSectionIDs = visibleActionSectionIDs.intersection(validIDs)
        visibleNoteSectionIDs = visibleNoteSectionIDs.intersection(validIDs)
        visibleNoteOptionsSectionIDs = visibleNoteOptionsSectionIDs.intersection(validIDs)
        visibleResolvedNoteSectionIDs = visibleResolvedNoteSectionIDs.intersection(validIDs)
        noteDraftBySection = noteDraftBySection.filter { validIDs.contains($0.key) }
        sectionTags = sectionTags.filter { validIDs.contains($0.key) }
        taggedTextBySection = taggedTextBySection.filter { validIDs.contains($0.key) }

        editingNoteKeys = editingNoteKeys.filter { noteKey in
            validIDs.contains { id in noteKey.hasPrefix("\(id.uuidString)-") }
        }

        if let key = revealedResolveNoteKey,
           !validIDs.contains(where: { key.hasPrefix("\($0.uuidString)-") }) {
            revealedResolveNoteKey = nil
        }

        DispatchQueue.main.async {
            self.isApplyingUndo = false
            self.isApplyingRedo = false
        }
    }

    func redoLastProjectChange() {
        guard let nextSnapshot = projectRedoStack.popLast() else { return }

        pushUndoSnapshot(currentSnapshot())

        isApplyingRedo = true
        applySnapshot(nextSnapshot)

        let validIDs = Set(sections.map(\.id))
        if let activeSectionID, !validIDs.contains(activeSectionID) {
            self.activeSectionID = sections.first?.id
        }

        textViews = textViews.filter { validIDs.contains($0.key) }
        sectionHeights = sectionHeights.filter { validIDs.contains($0.key) }
        caretIndexBySection = caretIndexBySection.filter { validIDs.contains($0.key) }
        visibleActionSectionIDs = visibleActionSectionIDs.intersection(validIDs)
        visibleNoteSectionIDs = visibleNoteSectionIDs.intersection(validIDs)
        visibleNoteOptionsSectionIDs = visibleNoteOptionsSectionIDs.intersection(validIDs)
        visibleResolvedNoteSectionIDs = visibleResolvedNoteSectionIDs.intersection(validIDs)
        noteDraftBySection = noteDraftBySection.filter { validIDs.contains($0.key) }
        sectionTags = sectionTags.filter { validIDs.contains($0.key) }
        taggedTextBySection = taggedTextBySection.filter { validIDs.contains($0.key) }

        editingNoteKeys = editingNoteKeys.filter { noteKey in
            validIDs.contains { id in noteKey.hasPrefix("\(id.uuidString)-") }
        }

        if let key = revealedResolveNoteKey,
           !validIDs.contains(where: { key.hasPrefix("\($0.uuidString)-") }) {
            revealedResolveNoteKey = nil
        }

        DispatchQueue.main.async {
            self.isApplyingUndo = false
            self.isApplyingRedo = false
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
        editingNoteKeys = editingNoteKeys.filter { !$0.hasPrefix("\(id.uuidString)-") }

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

        editingNoteKeys = editingNoteKeys.filter { !$0.hasPrefix("\(sectionID.uuidString)-") }

        let note = sections[idx].notes.remove(at: noteIndex)
        sections[idx].resolvedNotes.append(note)
        revealedResolveNoteKey = nil
    }

    func deleteNote(sectionID: UUID, noteIndex: Int) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }),
              sections[idx].notes.indices.contains(noteIndex) else { return }

        editingNoteKeys = editingNoteKeys.filter { !$0.hasPrefix("\(sectionID.uuidString)-") }
        sections[idx].notes.remove(at: noteIndex)
        revealedResolveNoteKey = nil
    }

    func deleteResolvedNote(sectionID: UUID, resolvedIndex: Int) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }),
              sections[idx].resolvedNotes.indices.contains(resolvedIndex) else { return }

        sections[idx].resolvedNotes.remove(at: resolvedIndex)
        visibleResolvedNoteSectionIDs.insert(sectionID)
    }

    func openAllSectionsInWindows() {
        guard !sections.isEmpty, !openingAllSectionWindows else { return }

        if allSectionWindowsVisible {
            openingAllSectionWindows = true
            Task { @MainActor in
                dismissWindow(id: "section-window")
                model.showSectionNumbersInWindows = false
                model.elevateSectionWindowsForBulkOpen = false
                allSectionWindowsVisible = false
                openingAllSectionWindows = false
            }
            return
        }

        sectionWindowSelection = []
        showingSectionWindowPickerSheet = true
    }

    func openSectionsInWindows(ids: Set<UUID>) {
        guard !openingAllSectionWindows else { return }
        let orderedIDs = sections.map(\.id).filter { ids.contains($0) }
        guard !orderedIDs.isEmpty else { return }

        openingAllSectionWindows = true

        Task { @MainActor in
            model.showSectionNumbersInWindows = true
            model.elevateSectionWindowsForBulkOpen = true
            dismissWindow(id: "section-window")
            try? await Task.sleep(nanoseconds: 500_000_000)

            let columns = 3

            for (index, sectionID) in orderedIDs.enumerated() {
                openWindow(id: "section-window", value: sectionID)

                let isEndOfRow = ((index + 1) % columns == 0)
                if isEndOfRow {
                    try? await Task.sleep(nanoseconds: 420_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            model.showSectionNumbersInWindows = false
            model.elevateSectionWindowsForBulkOpen = false
            allSectionWindowsVisible = true
            openingAllSectionWindows = false
        }
    }

    func clearAllNotes(in sectionID: UUID) {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return }

        sections[idx].notes.removeAll()
        sections[idx].resolvedNotes.removeAll()
        noteDraftBySection[sectionID] = ""

        visibleNoteSectionIDs.remove(sectionID)
        visibleResolvedNoteSectionIDs.remove(sectionID)

        editingNoteKeys = editingNoteKeys.filter { !$0.hasPrefix("\(sectionID.uuidString)-") }
        if let key = revealedResolveNoteKey, key.hasPrefix("\(sectionID.uuidString)-") {
            revealedResolveNoteKey = nil
        }
    }

    private var pendingNoteDeletionTitle: String {
        guard let pendingNoteDeletion else { return "Delete item?" }

        switch pendingNoteDeletion {
        case .resolvedNote(let sectionID, let resolvedIndex):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            return "Delete resolved note from Section \(sectionNumber)?"

        case .clearAll(let sectionID):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            return "Clear all notes from Section \(sectionNumber)?"
        }
    }

    private var pendingNoteDeletionMessage: String {
        guard let pendingNoteDeletion else { return "This action cannot be undone." }

        switch pendingNoteDeletion {
        case .resolvedNote(let sectionID, let resolvedIndex):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            if let notePreview = resolvedNotePreview(for: sectionID, resolvedIndex: resolvedIndex) {
                return "This will delete one resolved note from Section \(sectionNumber): \(notePreview)"
            }
            return "This will delete one resolved note from Section \(sectionNumber)."

        case .clearAll(let sectionID):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            let noteCount = noteDeletionCount(for: sectionID)
            return "This will delete \(noteCount) note\(noteCount == 1 ? "" : "s") from Section \(sectionNumber)."
        }
    }

    private var pendingSectionDeletionTitle: String {
        guard let pendingSectionDeletion else { return "Delete section?" }

        switch pendingSectionDeletion {
        case .section(let sectionID):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            return "Delete Section \(sectionNumber)?"
        }
    }

    private var pendingSectionDeletionMessage: String {
        guard let pendingSectionDeletion else { return "This action cannot be undone." }

        switch pendingSectionDeletion {
        case .section(let sectionID):
            let sectionNumber = originalSectionIndex(for: sectionID) + 1
            return "This will move Section \(sectionNumber) to the graveyard."
        }
    }

    private func noteDeletionCount(for sectionID: UUID) -> Int {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return 0 }
        return sections[idx].notes.count + sections[idx].resolvedNotes.count
    }

    private func resolvedNotePreview(for sectionID: UUID, resolvedIndex: Int, limit: Int = 80) -> String? {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }),
              sections[idx].resolvedNotes.indices.contains(resolvedIndex) else { return nil }

        return trimmedPreview(for: sections[idx].resolvedNotes[resolvedIndex], limit: limit)
    }

    private func sectionPreview(for sectionID: UUID, limit: Int = 80) -> String? {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return nil }
        return trimmedPreview(for: sections[idx].text, limit: limit)
    }

    private func trimmedPreview(for text: String, limit: Int) -> String? {
        let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else { return nil }
        if preview.count <= limit {
            return preview
        }
        return String(preview.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    enum TextStyle: String {
        case bold
        case italic
        case underline
        case strikethrough

        var markers: (prefix: String, suffix: String) {
            switch self {
            case .bold:
                return ("**", "**")
            case .italic:
                return ("*", "*")
            case .underline:
                return ("__", "__")
            case .strikethrough:
                return ("~~", "~~")
            }
        }
    }

    enum TextColorStyle: String {
        case red
        case blue
        case green
        case purple

        var uiColor: UIColor {
            switch self {
            case .red: return .systemRed
            case .blue: return .systemBlue
            case .green: return .systemGreen
            case .purple: return .systemPurple
            }
        }

        var docxHexValue: String {
            switch self {
            case .red: return "FF3B30"
            case .blue: return "0A84FF"
            case .green: return "30D158"
            case .purple: return "BF5AF2"
            }
        }
    }

    enum TextFontTypeStyle: String {
        case system
        case serif
        case rounded
        case monospaced

        var design: Font.Design? {
            switch self {
            case .system: return nil
            case .serif: return .serif
            case .rounded: return .rounded
            case .monospaced: return .monospaced
            }
        }

        var uiKitDesign: UIFontDescriptor.SystemDesign? {
            switch self {
            case .system: return nil
            case .serif: return .serif
            case .rounded: return .rounded
            case .monospaced: return .monospaced
            }
        }

        var docxFontName: String {
            switch self {
            case .system: return "Aptos"
            case .serif: return "Times New Roman"
            case .rounded: return "Avenir Next Rounded"
            case .monospaced: return "Courier New"
            }
        }
    }

    enum TextFontSizeStyle: String {
        case small
        case medium
        case large
        case extraLarge

        var pointSize: CGFloat {
            switch self {
            case .small: return 18
            case .medium: return 25
            case .large: return 32
            case .extraLarge: return 40
            }
        }

        static func pointSize(for styleValue: String) -> CGFloat? {
            if let preset = TextFontSizeStyle(rawValue: styleValue) {
                return preset.pointSize
            }

            let prefix = "custom:"
            guard styleValue.hasPrefix(prefix) else { return nil }
            return CGFloat(Double(styleValue.dropFirst(prefix.count)) ?? 0)
        }
    }

    enum TextHighlightStyle: String {
        case yellow
        case orange
        case green
        case pink
        case blue

        var uiColor: UIColor {
            switch self {
            case .yellow: return .systemYellow.withAlphaComponent(0.45)
            case .orange: return .systemOrange.withAlphaComponent(0.35)
            case .green: return .systemGreen.withAlphaComponent(0.30)
            case .pink: return .systemPink.withAlphaComponent(0.30)
            case .blue: return .systemBlue.withAlphaComponent(0.25)
            }
        }

        var docxValue: String {
            switch self {
            case .yellow: return "yellow"
            case .orange: return "darkYellow"
            case .green: return "green"
            case .pink: return "magenta"
            case .blue: return "blue"
            }
        }

        var docxShadingFillHex: String {
            switch self {
            case .yellow: return "FFF59D"
            case .orange: return "FFCC80"
            case .green: return "C5E1A5"
            case .pink: return "F8BBD0"
            case .blue: return "B3E5FC"
            }
        }
    }

    func applyStyle(_ style: TextStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        captureUndoBeforeTextStyleChange()

        switch style {
        case .bold:
            toggleTextStyleRange(selectedRange, in: &sections[index].boldStyles, style: style.rawValue)
        case .italic:
            toggleTextStyleRange(selectedRange, in: &sections[index].italicStyles, style: style.rawValue)
        case .underline:
            toggleTextStyleRange(selectedRange, in: &sections[index].underlineStyles, style: style.rawValue)
        case .strikethrough:
            toggleTextStyleRange(selectedRange, in: &sections[index].strikethroughStyles, style: style.rawValue)
        }
    }

    func applyTextColor(_ color: TextColorStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        toggleTextStyleRange(selectedRange, in: &sections[index].colors, style: color.rawValue)
    }

    func applyTextHighlight(_ highlight: TextHighlightStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        toggleTextStyleRange(selectedRange, in: &sections[index].highlights, style: highlight.rawValue)
    }

    func applyTextFontType(_ fontType: TextFontTypeStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        toggleTextStyleRange(selectedRange, in: &sections[index].fontTypes, style: fontType.rawValue)
    }

    func applyTextFontSize(_ fontSize: TextFontSizeStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        toggleTextStyleRange(selectedRange, in: &sections[index].fontSizes, style: fontSize.rawValue)
    }

    func applyTextFontSize(_ pointSize: CGFloat) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }

        let nsText = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= nsText.length else { return }

        let roundedPointSize = Int(pointSize.rounded())
        toggleTextStyleRange(selectedRange, in: &sections[index].fontSizes, style: "custom:\(roundedPointSize)")
    }

    @ViewBuilder
    private func colorPaletteRow(title: String, color: UIColor) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(uiColor: color))
                .frame(width: 12, height: 12)

            Text(title)
        }
    }

    @ViewBuilder
    private func fontTypeRow(title: String, design: Font.Design?) -> some View {
        if let design {
            Text(title)
                .font(.system(size: 16, design: design))
        } else {
            Text(title)
                .font(.system(size: 16))
        }
    }

    @ViewBuilder
    private var customFontSizeCenteredPopup: some View {
        HStack(spacing: 8) {
            Button {
                adjustCustomFontSize(by: -1)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .disabled(customFontSizeValue <= 8)

            TextField("", value: $customFontSizeValue, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)

            Button {
                adjustCustomFontSize(by: 1)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(customFontSizeValue >= 96)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func swatchImage(_ color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return UIImage(systemName: "circle.fill", withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    private func adjustCustomFontSize(by delta: Double) {
        customFontSizeValue = min(max(customFontSizeValue + delta, 8), 96)
    }

    private func closeCustomFontSizePopup() {
        applyTextFontSize(customFontSizeValue)
        showingCustomFontSizeSheet = false
    }

    private func toggleTextStyleRange(_ selectedRange: NSRange, in ranges: inout [TextStyleRange], style: String) {
        if let existingIndex = ranges.firstIndex(where: { $0.location == selectedRange.location && $0.length == selectedRange.length }) {
            if ranges[existingIndex].style == style {
                ranges.remove(at: existingIndex)
            } else {
                ranges[existingIndex].style = style
            }
        } else {
            ranges.append(TextStyleRange(location: selectedRange.location, length: selectedRange.length, style: style))
        }
    }

    private func captureUndoBeforeTextStyleChange() {
        captureUndoBeforeTagChange()
    }

    func toggleTagOnActiveSection(_ tag: String) {
        guard let activeSectionID = activeSectionID else { return }

        if let selectedText = currentlySelectedText(in: activeSectionID), !selectedText.isEmpty {
            let currentTags = taggedTextBySection[activeSectionID]?[selectedText] ?? []

            if currentTags.contains(tag) {
                captureUndoBeforeTagChange()
                taggedTextBySection[activeSectionID]?[selectedText]?.remove(tag)

                if taggedTextBySection[activeSectionID]?[selectedText]?.isEmpty == true {
                    taggedTextBySection[activeSectionID]?.removeValue(forKey: selectedText)
                }

                if taggedTextBySection[activeSectionID]?.isEmpty == true {
                    taggedTextBySection[activeSectionID] = nil
                }
            } else {
                captureUndoBeforeTagChange()
                if taggedTextBySection[activeSectionID] == nil {
                    taggedTextBySection[activeSectionID] = [:]
                }
                if taggedTextBySection[activeSectionID]?[selectedText] == nil {
                    taggedTextBySection[activeSectionID]?[selectedText] = []
                }
                taggedTextBySection[activeSectionID]?[selectedText]?.insert(tag)
            }
        } else {
            if sectionTags[activeSectionID]?.contains(tag) == true {
                captureUndoBeforeTagChange()
                sectionTags[activeSectionID]?.remove(tag)
            } else {
                captureUndoBeforeTagChange()
                if sectionTags[activeSectionID] == nil {
                    sectionTags[activeSectionID] = []
                }
                sectionTags[activeSectionID]?.insert(tag)
            }
        }
    }

    func currentlySelectedText(in sectionID: UUID) -> String? {
        guard let textView = textViews[sectionID],
              let index = sections.firstIndex(where: { $0.id == sectionID }) else { return nil }

        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return nil }

        let text = sections[index].text as NSString
        guard selectedRange.location + selectedRange.length <= text.length else { return nil }

        let selectedText = text.substring(with: selectedRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedText.isEmpty ? nil : selectedText
    }

    func allTags(for sectionID: UUID) -> Set<String> {
        sectionLevelTags(for: sectionID).union(textLevelTags(for: sectionID))
    }

    func sectionLevelTags(for sectionID: UUID) -> Set<String> {
        sectionTags[sectionID] ?? []
    }

    func textLevelTags(for sectionID: UUID) -> Set<String> {
        Set(taggedTextBySection[sectionID]?.values.flatMap { $0 } ?? [])
    }

    func isTagAppliedInActiveContext(_ tag: String) -> Bool {
        guard let activeSectionID = activeSectionID else { return false }

        if let selectedText = currentlySelectedText(in: activeSectionID),
           let tagsForSelection = taggedTextBySection[activeSectionID]?[selectedText] {
            return tagsForSelection.contains(tag)
        }

        return allTags(for: activeSectionID).contains(tag)
    }

    enum TagApplicationState {
        case none
        case textOnly
        case sectionOnly
        case both
    }

    @ViewBuilder
    func tagStateMenuBadge(_ state: TagApplicationState) -> some View {
        switch state {
        case .none:
            EmptyView()
        case .textOnly:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.orange, .orange.opacity(0.20))
        case .sectionOnly:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.blue, .blue.opacity(0.20))
        case .both:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.orange, .blue, .blue.opacity(0.20))
        }
    }

    func tagApplicationStateInActiveContext(_ tag: String) -> TagApplicationState {
        guard let activeSectionID = activeSectionID else { return .none }

        let hasSectionTag = sectionLevelTags(for: activeSectionID).contains(tag)
        let hasTextTag: Bool

        if let selectedText = currentlySelectedText(in: activeSectionID),
           let tagsForSelection = taggedTextBySection[activeSectionID]?[selectedText] {
            hasTextTag = tagsForSelection.contains(tag)
        } else {
            hasTextTag = textLevelTags(for: activeSectionID).contains(tag)
        }

        switch (hasSectionTag, hasTextTag) {
        case (false, false): return .none
        case (false, true): return .textOnly
        case (true, false): return .sectionOnly
        case (true, true): return .both
        }
    }

    func hasSelectedTextInActiveSection() -> Bool {
        guard let activeSectionID else { return false }
        return (selectedLengthBySection[activeSectionID] ?? 0) > 0
    }

    func usedTagsInProject() -> Set<String> {
        var used: Set<String> = []
        for section in sections {
            used.formUnion(allTags(for: section.id))
        }
        return used
    }

    func hasFilterMatch(for filters: Set<String>) -> Bool {
        sections.contains { section in
            let tagsForSection = allTags(for: section.id)
            return filters.isSubset(of: tagsForSection)
        }
    }

    func filterableTags() -> [String] {
        customTagCategories
            .intersection(usedTagsInProject())
            .sorted()
    }

    func sanitizeActiveFilterTags() {
        let allowed = Set(filterableTags())
        if activeFilterTags != activeFilterTags.intersection(allowed) {
            activeFilterTags = activeFilterTags.intersection(allowed)
        }
    }

    func enforceTimelineAvailability() {
        if usedTagsInProject().isEmpty {
            showFilteredTimeline = false
        }
    }

    func currentSnapshot() -> ProjectEditSnapshot {
        ProjectEditSnapshot(
            sections: sections,
            sectionTags: sectionTags,
            taggedTextBySection: taggedTextBySection
        )
    }

    func applySnapshot(_ snapshot: ProjectEditSnapshot) {
        sections = snapshot.sections
        sectionTags = snapshot.sectionTags
        taggedTextBySection = snapshot.taggedTextBySection
    }

    func pushUndoSnapshot(_ snapshot: ProjectEditSnapshot) {
        projectUndoStack.append(snapshot)
        projectRedoStack.removeAll()
        if projectUndoStack.count > 200 {
            projectUndoStack.removeFirst(projectUndoStack.count - 200)
        }
    }

    func pushRedoSnapshot(_ snapshot: ProjectEditSnapshot) {
        projectRedoStack.append(snapshot)
        if projectRedoStack.count > 200 {
            projectRedoStack.removeFirst(projectRedoStack.count - 200)
        }
    }

    func captureUndoBeforeTagChange() {
        guard !isApplyingUndo && !isApplyingRedo else { return }
        pushUndoSnapshot(currentSnapshot())
    }

    func presentTagActions(for sectionID: UUID) {
        let sectionTags = sectionLevelTags(for: sectionID).sorted()
        let textTags = textLevelTags(for: sectionID).sorted()
        guard !sectionTags.isEmpty || !textTags.isEmpty else { return }

        tagActionSectionID = sectionID
        tagActionSectionTags = sectionTags
        tagActionTextTags = textTags
    }

    func removeSectionTag(_ tag: String, from sectionID: UUID) {
        guard sectionTags[sectionID]?.contains(tag) == true else { return }

        captureUndoBeforeTagChange()
        sectionTags[sectionID]?.remove(tag)
        if sectionTags[sectionID]?.isEmpty == true {
            sectionTags[sectionID] = nil
        }
    }

    func removeTextTag(_ tag: String, from sectionID: UUID) {
        guard var snippets = taggedTextBySection[sectionID] else { return }

        let hadTag = snippets.values.contains { $0.contains(tag) }
        guard hadTag else { return }

        captureUndoBeforeTagChange()

        for key in snippets.keys {
            snippets[key]?.remove(tag)
        }

        snippets = snippets.filter { !$0.value.isEmpty }
        taggedTextBySection[sectionID] = snippets.isEmpty ? nil : snippets
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
    var highlightedSnippets: Set<String> = []
    var textColors: [TextStyleRange] = []
    var textHighlights: [TextStyleRange] = []
    var textFontTypes: [TextStyleRange] = []
    var textFontSizes: [TextStyleRange] = []
    var textBoldStyles: [TextStyleRange] = []
    var textItalicStyles: [TextStyleRange] = []
    var textUnderlineStyles: [TextStyleRange] = []
    var textStrikethroughStyles: [TextStyleRange] = []
    var splitMode: Bool
    @Binding var snappedY: CGFloat
    var onSplit: (CGFloat) -> Void
    var onAttach: (UITextView) -> Void
    var onSelectionChange: (Int, Int) -> Void
    @Binding var calculatedHeight: CGFloat
    var onHighlightedSnippetAnchorsChange: (([String: [CGPoint]]) -> Void)? = nil
    var selectionMenuBuilder: (([UIMenuElement]) -> UIMenu?)? = nil

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
            self.onSelectionChange(view.selectedRange.location, view.selectedRange.length)
        }
        
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let selectedRange = uiView.selectedRange
        uiView.attributedText = makeAttributedText(from: text)

        let clampedLocation = min(selectedRange.location, uiView.attributedText.length)
        let maxLength = max(0, uiView.attributedText.length - clampedLocation)
        let clampedLength = min(selectedRange.length, maxLength)
        uiView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)

//        context.coordinator.splitMode = splitMode
//        uiView.isEditable = true
//        uiView.isSelectable = true
        
        DispatchQueue.main.async {
            let newHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)).height
            if self.calculatedHeight != newHeight {
                self.calculatedHeight = newHeight
            }

            self.onHighlightedSnippetAnchorsChange?(self.computeSnippetAnchorPoints(in: uiView))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func makeAttributedText(from text: String) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([
            .font: UIFont.systemFont(ofSize: 25),
            .foregroundColor: UIColor.label
        ], range: fullRange)

        applyFontTypeStyles(to: attributed, text: text, fontTypes: textFontTypes)
        applyFontSizeStyles(to: attributed, text: text, fontSizes: textFontSizes)
        applyBoldStyles(to: attributed, text: text, boldStyles: textBoldStyles)
        applyItalicStyles(to: attributed, text: text, italicStyles: textItalicStyles)
        applyUnderlineStyles(to: attributed, text: text, underlineStyles: textUnderlineStyles)
        applyStrikethroughStyles(to: attributed, text: text, strikethroughStyles: textStrikethroughStyles)
        applyColorStyles(to: attributed, text: text, colors: textColors)
        applyHighlightStyles(to: attributed, text: text, highlights: textHighlights)

        for snippet in highlightedSnippets where !snippet.isEmpty {
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)

            while true {
                let found = nsText.range(of: snippet, options: [], range: searchRange)
                if found.location == NSNotFound { break }

                attributed.addAttribute(
                    .backgroundColor,
                    value: UIColor.systemOrange.withAlphaComponent(0.30),
                    range: found
                )

                let nextStart = found.location + found.length
                if nextStart >= nsText.length { break }
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            }
        }

        return attributed
    }

    private func applyHighlightStyles(to attributed: NSMutableAttributedString, text: String, highlights: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in highlights {
            guard let style = ProjectDetailView.TextHighlightStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.backgroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyColorStyles(to attributed: NSMutableAttributedString, text: String, colors: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in colors {
            guard let style = ProjectDetailView.TextColorStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.foregroundColor, value: style.uiColor, range: nsRange)
        }
    }

    private func applyFontTypeStyles(to attributed: NSMutableAttributedString, text: String, fontTypes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontTypes {
            guard let style = ProjectDetailView.TextFontTypeStyle(rawValue: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let font: UIFont
            if let design = style.uiKitDesign, let designedFont = existingFont.fontDescriptor.withDesign(design).flatMap({ UIFont(descriptor: $0, size: existingFont.pointSize) }) {
                font = designedFont
            } else {
                font = UIFont.systemFont(ofSize: existingFont.pointSize)
            }

            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private func applyFontSizeStyles(to attributed: NSMutableAttributedString, text: String, fontSizes: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in fontSizes {
            guard let pointSize = ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style) else { continue }
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let font = existingFont.withSize(pointSize)
            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private func applyBoldStyles(to attributed: NSMutableAttributedString, text: String, boldStyles: [TextStyleRange]) {
        applyFontTraitStyles(to: attributed, text: text, ranges: boldStyles, trait: .traitBold)
    }

    private func applyItalicStyles(to attributed: NSMutableAttributedString, text: String, italicStyles: [TextStyleRange]) {
        applyFontTraitStyles(to: attributed, text: text, ranges: italicStyles, trait: .traitItalic)
    }

    private func applyUnderlineStyles(to attributed: NSMutableAttributedString, text: String, underlineStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in underlineStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyStrikethroughStyles(to attributed: NSMutableAttributedString, text: String, strikethroughStyles: [TextStyleRange]) {
        let textLength = (text as NSString).length

        for range in strikethroughStyles {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyFontTraitStyles(to attributed: NSMutableAttributedString, text: String, ranges: [TextStyleRange], trait: UIFontDescriptor.SymbolicTraits) {
        let textLength = (text as NSString).length

        for range in ranges {
            let nsRange = range.nsRange
            guard nsRange.location >= 0, nsRange.length > 0, nsRange.location + nsRange.length <= textLength else { continue }

            let existingFont = attributed.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 25)
            let combinedTraits = existingFont.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = existingFont.fontDescriptor.withSymbolicTraits(combinedTraits) {
                let font = UIFont(descriptor: descriptor, size: existingFont.pointSize)
                attributed.addAttribute(.font, value: font, range: nsRange)
            }
        }
    }

    private func computeSnippetAnchorPoints(in textView: UITextView) -> [String: [CGPoint]] {
        guard !highlightedSnippets.isEmpty else { return [:] }

        var result: [String: [CGPoint]] = [:]
        let text = textView.text ?? ""
        let nsText = text as NSString
        let layoutManager = textView.layoutManager

        for snippet in highlightedSnippets where !snippet.isEmpty {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while true {
                let found = nsText.range(of: snippet, options: [], range: searchRange)
                if found.location == NSNotFound { break }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: found, actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)

                rect.origin.x += textView.textContainerInset.left
                rect.origin.y += textView.textContainerInset.top - textView.contentOffset.y

                let anchor = CGPoint(x: rect.minX, y: rect.minY)
                result[snippet, default: []].append(anchor)

                let nextStart = found.location + found.length
                if nextStart >= nsText.length { break }
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            }
        }

        return result
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
            parent.onSelectionChange(textView.selectedRange.location, textView.selectedRange.length)
        }

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn textRange: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            parent.selectionMenuBuilder?(suggestedActions)
        }
    }
}

struct Section: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var notes: [String] = []
    var resolvedNotes: [String] = []
    var colors: [TextStyleRange] = []
    var highlights: [TextStyleRange] = []
    var fontTypes: [TextStyleRange] = []
    var fontSizes: [TextStyleRange] = []
    var boldStyles: [TextStyleRange] = []
    var italicStyles: [TextStyleRange] = []
    var underlineStyles: [TextStyleRange] = []
    var strikethroughStyles: [TextStyleRange] = []

    init(id: UUID, text: String, notes: [String] = [], resolvedNotes: [String] = [], colors: [TextStyleRange] = [], highlights: [TextStyleRange] = [], fontTypes: [TextStyleRange] = [], fontSizes: [TextStyleRange] = [], boldStyles: [TextStyleRange] = [], italicStyles: [TextStyleRange] = [], underlineStyles: [TextStyleRange] = [], strikethroughStyles: [TextStyleRange] = []) {
        self.id = id
        self.text = text
        self.notes = notes
        self.resolvedNotes = resolvedNotes
        self.colors = colors
        self.highlights = highlights
        self.fontTypes = fontTypes
        self.fontSizes = fontSizes
        self.boldStyles = boldStyles
        self.italicStyles = italicStyles
        self.underlineStyles = underlineStyles
        self.strikethroughStyles = strikethroughStyles
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case notes
        case resolvedNotes
        case colors
        case highlights
        case fontTypes
        case fontSizes
        case boldStyles
        case italicStyles
        case underlineStyles
        case strikethroughStyles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        resolvedNotes = try container.decodeIfPresent([String].self, forKey: .resolvedNotes) ?? []
        colors = try container.decodeIfPresent([TextStyleRange].self, forKey: .colors) ?? []
        highlights = try container.decodeIfPresent([TextStyleRange].self, forKey: .highlights) ?? []
        fontTypes = try container.decodeIfPresent([TextStyleRange].self, forKey: .fontTypes) ?? []
        fontSizes = try container.decodeIfPresent([TextStyleRange].self, forKey: .fontSizes) ?? []
        boldStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .boldStyles) ?? []
        italicStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .italicStyles) ?? []
        underlineStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .underlineStyles) ?? []
        strikethroughStyles = try container.decodeIfPresent([TextStyleRange].self, forKey: .strikethroughStyles) ?? []
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

    var sections: [Section]

    init(text: String = "") {
        self.sections = text.isEmpty ? [] : [Section(id: UUID(), text: text)]
    }

    init(sections: [Section]) {
        self.sections = sections
    }

    init(configuration: ReadConfiguration) throws {
        let text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        sections = text.isEmpty ? [] : [Section(id: UUID(), text: text)]
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

    private static func writeDocxArchive(sections: [Section], to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let paragraphs = sections.isEmpty ? [Section(id: UUID(), text: "(Empty project)")] : sections

        let bodyXML = paragraphs.map { paragraph in
            let cleaned = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return "<w:p/>"
            }

            return styledParagraphXML(for: paragraph)
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

    private static func styledParagraphXML(for section: Section) -> String {
        let text = section.text
        let nsText = text as NSString
        guard nsText.length > 0 else { return "<w:p/>" }

        var runs: [String] = []
        var currentText = ""
        var currentState = WordStyleState()

        func flushCurrentText() {
            guard !currentText.isEmpty else { return }
            runs.append(
                formatRun(
                    currentText,
                    state: currentState,
                    superscript: false,
                    subscript_: false
                )
            )
            currentText = ""
        }

        for index in 0..<nsText.length {
            let character = nsText.substring(with: NSRange(location: index, length: 1))

            if character == "\n" || character == "\r" {
                flushCurrentText()
                if character == "\r", index + 1 < nsText.length {
                    let nextCharacter = nsText.substring(with: NSRange(location: index + 1, length: 1))
                    if nextCharacter == "\n" {
                        continue
                    }
                }
                runs.append("<w:r><w:br/></w:r>")
                continue
            }

            let newState = WordStyleState(
                bold: sectionHasStyle(section.boldStyles, at: index),
                italic: sectionHasStyle(section.italicStyles, at: index),
                underline: sectionHasStyle(section.underlineStyles, at: index),
                strikethrough: sectionHasStyle(section.strikethroughStyles, at: index),
                color: sectionColorStyle(section.colors, at: index),
                highlight: sectionHighlightStyle(section.highlights, at: index),
                fontType: sectionFontTypeStyle(section.fontTypes, at: index),
                fontSize: sectionFontSizeStyle(section.fontSizes, at: index)
            )

            if currentText.isEmpty {
                currentState = newState
                currentText.append(character)
            } else if newState == currentState {
                currentText.append(character)
            } else {
                flushCurrentText()
                currentState = newState
                currentText.append(character)
            }
        }

        flushCurrentText()
        return "<w:p>\(runs.joined())</w:p>"
    }

    private static func sectionHasStyle(_ ranges: [TextStyleRange], at index: Int) -> Bool {
        ranges.contains { index >= $0.location && index < $0.location + $0.length }
    }

    private static func sectionColorStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextColorStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextColorStyle(rawValue: range.style)
    }

    private static func sectionHighlightStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextHighlightStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextHighlightStyle(rawValue: range.style)
    }

    private static func sectionFontTypeStyle(_ ranges: [TextStyleRange], at index: Int) -> ProjectDetailView.TextFontTypeStyle? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextFontTypeStyle(rawValue: range.style)
    }

    private static func sectionFontSizeStyle(_ ranges: [TextStyleRange], at index: Int) -> CGFloat? {
        guard let range = ranges.last(where: { index >= $0.location && index < $0.location + $0.length }) else { return nil }
        return ProjectDetailView.TextFontSizeStyle.pointSize(for: range.style)
    }

    private struct WordStyleState: Equatable {
        let bold: Bool
        let italic: Bool
        let underline: Bool
        let strikethrough: Bool
        let color: ProjectDetailView.TextColorStyle?
        let highlight: ProjectDetailView.TextHighlightStyle?
        let fontType: ProjectDetailView.TextFontTypeStyle?
        let fontSize: CGFloat?

        init(
            bold: Bool = false,
            italic: Bool = false,
            underline: Bool = false,
            strikethrough: Bool = false,
            color: ProjectDetailView.TextColorStyle? = nil,
            highlight: ProjectDetailView.TextHighlightStyle? = nil,
            fontType: ProjectDetailView.TextFontTypeStyle? = nil,
            fontSize: CGFloat? = nil
        ) {
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
            self.color = color
            self.highlight = highlight
            self.fontType = fontType
            self.fontSize = fontSize
        }
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

    private static func formatRun(_ text: String, state: WordStyleState, superscript: Bool, subscript_: Bool) -> String {
        let escaped = xmlEscape(text)
        var xml = "<w:r>"
        
        if (state.bold || state.italic || state.underline || state.strikethrough || state.color != nil || state.highlight != nil || state.fontType != nil || state.fontSize != nil || superscript || subscript_
        ) {
            xml += "<w:rPr>"
            if let fontType = state.fontType {
                xml += "<w:rFonts w:ascii=\"\(fontType.docxFontName)\" w:hAnsi=\"\(fontType.docxFontName)\" w:cs=\"\(fontType.docxFontName)\"/>"
            }
            if state.bold {
                xml += "<w:b/>"
            }
            if state.italic {
                xml += "<w:i/>"
            }
            if state.strikethrough {
                xml += "<w:strike/>"
            }
            if let color = state.color {
                xml += "<w:color w:val=\"\(color.docxHexValue)\"/>"
            }
            if let fontSize = state.fontSize {
                let halfPoints = Int((fontSize * 2).rounded())
                xml += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
            }
            if let highlight = state.highlight {
                xml += "<w:highlight w:val=\"\(highlight.docxValue)\"/>"
            }
            if state.underline {
                xml += "<w:u w:val=\"single\"/>"
            }
            if let highlight = state.highlight {
                xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(highlight.docxShadingFillHex)\"/>"
            }
            if superscript {
                xml += "<w:vertAlign w:val=\"superscript\"/>"
            }
            if subscript_ {
                xml += "<w:vertAlign w:val=\"subscript\"/>"
            }
            xml += "</w:rPr>"
        }
        
        xml += "<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
        return xml
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

struct SectionWindowPickerSheet: View {
    let sections: [Section]
    @Binding var selection: Set<UUID>
    var onCancel: () -> Void
    var onConfirm: (Set<UUID>) -> Void

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    Toggle(isOn: Binding(
                        get: { !sections.isEmpty && selection.count == sections.count },
                        set: { newValue in
                            selection = newValue ? Set(sections.map(\.id)) : []
                        }
                    )) {
                        Text("Select All")
                    }
                }

                SwiftUI.Section("Sections") {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        Button {
                            if selection.contains(section.id) {
                                selection.remove(section.id)
                            } else {
                                selection.insert(section.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selection.contains(section.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selection.contains(section.id) ? Color.accentColor : Color.secondary)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Section \(index + 1)")
                                        .font(.headline)
                                    Text(sectionPreview(for: section))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Open Sections in Windows")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open Windows") {
                        onConfirm(selection)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 640)
    }

    private func sectionPreview(for section: Section) -> String {
        let trimmed = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(Empty section)" }
        return String(trimmed.prefix(160))
    }
}

