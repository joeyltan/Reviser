import SwiftUI
import RadixUI
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

struct ProjectDetailView: View {
    struct ProjectEditSnapshot: Equatable {
        var sections: [Section]
        var sectionTags: [UUID: Set<String>]
        var taggedTextBySection: [UUID: [String: Set<String>]]
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

    @State private var activeSectionID: UUID?
    @State private var caretIndexBySection: [UUID: Int] = [:]
    @State private var selectedLengthBySection: [UUID: Int] = [:]
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var visibleActionSectionIDs: Set<UUID> = []
    @State private var visibleNoteSectionIDs: Set<UUID> = []
    @State private var visibleNoteOptionsSectionIDs: Set<UUID> = []
    @State private var visibleResolvedNoteSectionIDs: Set<UUID> = []
    @State private var revealedResolveNoteKey: String? = nil
    @State private var noteDraftBySection: [UUID: String] = [:]
    @State private var editingNoteKeys: Set<String> = []
    @State private var openingAllSectionWindows: Bool = false
    @State private var allSectionWindowsVisible: Bool = false
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
            .confirmationDialog(
                "Tag options",
                isPresented: Binding(
                    get: { tagActionSectionID != nil },
                    set: { isPresented in
                        if !isPresented {
                            tagActionSectionID = nil
                            tagActionSectionTags = []
                            tagActionTextTags = []
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let sectionID = tagActionSectionID {
                    if !tagActionSectionTags.isEmpty {
                        SwiftUI.Section("Remove section tag") {
                            ForEach(tagActionSectionTags, id: \.self) { tag in
                                Button("Delete \(tag) (Section)", role: .destructive) {
                                    removeSectionTag(tag, from: sectionID)
                                }
                            }
                        }
                    }

                    if !tagActionSectionTags.isEmpty && !tagActionTextTags.isEmpty {
                        Divider()
                    }

                    if !tagActionTextTags.isEmpty {
                        SwiftUI.Section("Remove text tag") {
                            ForEach(tagActionTextTags, id: \.self) { tag in
                                Button("Delete \(tag) (Text)", role: .destructive) {
                                    removeTextTag(tag, from: sectionID)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                projectUndoStack.removeAll()
                projectRedoStack.removeAll()
                hasInitializedSectionHistory = false
                isApplyingUndo = false
                isApplyingRedo = false
                isSyncingSectionsFromModel = true
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
            .onChange(of: sections) { oldSections, newSections in
                if !hasInitializedSectionHistory {
                    hasInitializedSectionHistory = true
                } else if !isApplyingUndo && !isApplyingRedo && !isSyncingSectionsFromModel && oldSections != newSections {
                    let oldSnapshot = ProjectEditSnapshot(
                        sections: oldSections,
                        sectionTags: sectionTags,
                        taggedTextBySection: taggedTextBySection
                    )
                    pushUndoSnapshot(oldSnapshot)
                }

                if isApplyingUndo {
                    isApplyingUndo = false
                }

                if isApplyingRedo {
                    isApplyingRedo = false
                }

                if isSyncingSectionsFromModel {
                    isSyncingSectionsFromModel = false
                }

                model.updateProjectSections(id: projectID, sections: newSections)
                sanitizeActiveFilterTags()
            }
            .onChange(of: project.sections) { _, updatedSections in
                guard updatedSections != sections else { return }
                isSyncingSectionsFromModel = true
                sections = updatedSections
            }
            .onChange(of: sectionTags) { _, _ in
                sanitizeActiveFilterTags()
                enforceTimelineAvailability()
            }
            .onChange(of: taggedTextBySection) { _, _ in
                sanitizeActiveFilterTags()
                enforceTimelineAvailability()
            }
            .onChange(of: customTagCategories) { _, _ in
                sanitizeActiveFilterTags()
                enforceTimelineAvailability()
            }
            .onChange(of: activeFilterTags) { _, newFilters in
                guard !newFilters.isEmpty else { return }
                if !hasFilterMatch(for: newFilters) {
                    showingNoFilterMatchAlert = true
                }
            }

            .alert("No filter match", isPresented: $showingNoFilterMatchAlert) {
                Button("OK", role: .cancel) {}
            }
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
                .help(allSectionWindowsVisible ? "Close all section windows" : "Open all sections in ordered windows")

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
                        editingNoteKeys.removeAll()
                    }
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
                } label: {
                    Image(systemName: "wand.and.sparkles")
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
                    let availableFilterTags = filterableTags()
                    let hasAnyTaggedContent = !usedTagsInProject().isEmpty
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
            if shouldShowFilteredTimeline {
                linkedTimelineView()
                    .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(displayedSectionsForCurrentFilters(), id: \.id) { section in
                            sectionView(section: section, index: originalSectionIndex(for: section.id))
                        }
                    }
                    .padding(40)
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
                .offset(x: -36, y: 8)
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
                let manuscriptText = restitchedManuscriptText()
                if manuscriptText.isEmpty {
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
                    Text(LocalizedStringKey(manuscriptText))
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
        }
        .padding(24)
    }

    @ViewBuilder
    func sectionView(section: Section, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
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
                    )
                )
                .multilineTextAlignment(.leading)
                .frame(height: sectionHeights[section.id] ?? 100)
                .frame(maxWidth: .infinity)
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
                        .offset(x: -36, y: 8)
                    }
                }

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

                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let sectionIndex, editingNoteKeys.contains(noteKey) {
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
                        } else {
                            Text(notes[noteIndex])
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 6) {
                            if revealedResolveNoteKey == resolveKey {
                                Button {
                                    if editingNoteKeys.contains(noteKey) {
                                        editingNoteKeys.remove(noteKey)
                                    } else {
                                        editingNoteKeys.insert(noteKey)
                                    }
                                } label: {
                                    Group {
                                        if editingNoteKeys.contains(noteKey) {
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
                                .help(editingNoteKeys.contains(noteKey) ? "Save edit" : "Edit note")

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

                                    // Image(systemName: revealedResolveNoteKey == resolveKey ? "chevron.up" : "chevron.down")
                                    //     .font(.system(size: 12, weight: .semibold))
                                    //     .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(revealedResolveNoteKey == resolveKey ? "Hide note actions" : "Show note actions")
                        }
                        .frame(width: 120, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if revealedResolveNoteKey == resolveKey {
                            revealedResolveNoteKey = nil
                        } else {
                            revealedResolveNoteKey = resolveKey
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
                        clearAllNotes(in: sectionID)
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

    func openAllSectionsInWindows() {
        guard !sections.isEmpty, !openingAllSectionWindows else { return }

        openingAllSectionWindows = true

        Task { @MainActor in
            if allSectionWindowsVisible {
                dismissWindow(id: "section-window")
                model.showSectionNumbersInWindows = false
                model.elevateSectionWindowsForBulkOpen = false
                allSectionWindowsVisible = false
                openingAllSectionWindows = false
                return
            }

            model.showSectionNumbersInWindows = true
            model.elevateSectionWindowsForBulkOpen = true
            dismissWindow(id: "section-window")
            try? await Task.sleep(nanoseconds: 500_000_000)

            let columns = 3
            let sectionIDs = sections.map(\.id)

            for (index, sectionID) in sectionIDs.enumerated() {
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

    enum TextStyle {
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

    func applyStyle(_ style: TextStyle) {
        guard let activeSectionID = activeSectionID,
              let textView = textViews[activeSectionID],
              let index = sections.firstIndex(where: { $0.id == activeSectionID }) else { return }

        let selectedRange = textView.selectedRange
        let text = sections[index].text
        let selectedText = (text as NSString).substring(with: selectedRange)

        if selectedText.isEmpty {
            return
        }

        let markers = style.markers
        let styledText = markers.prefix + selectedText + markers.suffix

        // Replace selected text with styled version
        sections[index].text = (text as NSString).replacingCharacters(in: selectedRange, with: styledText)

        // Update the text view
        textView.text = sections[index].text

        // Move caret to after the styled text
        let newPosition = selectedRange.location + styledText.count
        textView.selectedRange = NSRange(location: newPosition, length: 0)
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
    var highlightedSnippets: Set<String> = []
    var splitMode: Bool
    @Binding var snappedY: CGFloat
    var onSplit: (CGFloat) -> Void
    var onAttach: (UITextView) -> Void
    var onSelectionChange: (Int, Int) -> Void
    @Binding var calculatedHeight: CGFloat
    var onHighlightedSnippetAnchorsChange: (([String: [CGPoint]]) -> Void)? = nil

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
                    let formattedRuns = markdownToWordXML(line)
                    if index == 0 {
                        return formattedRuns
                    } else {
                        return "<w:r><w:br/></w:r>\(formattedRuns)"
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

    private static func markdownToWordXML(_ text: String) -> String {
        var result = ""
        var i = text.startIndex
        var currentText = ""
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false
        var isSuperscript = false
        var isSubscript = false
        
        while i < text.endIndex {
            
            // Check for strikethrough (~~text~~)
            if i < text.index(text.endIndex, offsetBy: -1) && text[i] == "~" && text[text.index(after: i)] == "~" {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isStrikethrough.toggle()
                i = text.index(i, offsetBy: 2)
                continue
            }
            
            // Check for superscript (^text^)
            if text[i] == "^" {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isSuperscript.toggle()
                i = text.index(after: i)
                continue
            }
            
            // Check for subscript (_{text})
            if i < text.index(text.endIndex, offsetBy: -1) && text[i] == "_" && text[text.index(after: i)] == "{" {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isSubscript.toggle()
                i = text.index(i, offsetBy: text[text.index(after: i)] == "{" ? 2 : 1)
                continue
            }
            
            if text[i] == "}" && isSubscript {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isSubscript = false
                i = text.index(after: i)
                continue
            }
            
            // Check for bold (**text**)
            if i < text.index(text.endIndex, offsetBy: -1) && text[i] == "*" && text[text.index(after: i)] == "*" {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isBold.toggle()
                i = text.index(i, offsetBy: 2)
                continue
            }
            
            // Check for underline (__text__)
            if i < text.index(text.endIndex, offsetBy: -1) && text[i] == "_" && text[text.index(after: i)] == "_" {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isUnderline.toggle()
                i = text.index(i, offsetBy: 2)
                continue
            }
            
            // Check for italic (*text* or _text_)
            if (text[i] == "*" || text[i] == "_") && (i == text.startIndex || text[text.index(before: i)] != "\\") {
                if !currentText.isEmpty {
                    result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
                    currentText = ""
                }
                isItalic.toggle()
                i = text.index(after: i)
                continue
            }
            
            currentText.append(text[i])
            i = text.index(after: i)
        }
        
        if !currentText.isEmpty {
            result += formatRun(currentText, bold: isBold, italic: isItalic, underline: isUnderline, strikethrough: isStrikethrough, superscript: isSuperscript, subscript_: isSubscript)
        }
        
        return result
    }
    
    private static func formatRun(_ text: String, bold: Bool, italic: Bool, underline: Bool, strikethrough: Bool, superscript: Bool, subscript_: Bool) -> String {
        let escaped = xmlEscape(text)
        var xml = "<w:r>"
        
        if (bold || italic || underline || strikethrough || superscript || subscript_
        ) {
            xml += "<w:rPr>"
            if bold {
                xml += "<w:b/>"
            }
            if italic {
                xml += "<w:i/>"
            }
            if underline {
                xml += "<w:u w:val=\"single\"/>"
            }
            if strikethrough {
                xml += "<w:strike/>"
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

