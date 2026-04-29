import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sectionReorder = UTType(exportedAs: "com.reviser.section-reorder")
}

enum SectionsOverviewOrder {
    case row
    case column

    var label: String {
        switch self {
        case .row: return "Left to right"
        case .column: return "Top to bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .row: return "arrow.left.arrow.right"
        case .column: return "arrow.up.arrow.down"
        }
    }
}

struct SectionsWindowScene: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var sections: [Section] = []
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var currentProjectID: UUID?
    @State private var savedSectionOrder: [UUID] = []
    @State private var hasPendingReorder: Bool = false
    @State private var pendingTextSyncTask: Task<Void, Never>?
    @State private var overviewOrder: SectionsOverviewOrder = .row
    @State private var visibleSectionIDs: Set<UUID>? = nil
    @State private var showingSectionFilterSheet: Bool = false

    private var filterButtonLabel: String {
        guard let visibleSectionIDs else { return "All Sections" }
        return "\(visibleSectionIDs.count) of \(sections.count)"
    }

    var body: some View {
        Group {
            if currentProjectID != nil {
                NavigationStack {
                    SectionsGridView(
                        sections: $sections,
                        overviewOrder: $overviewOrder,
                        visibleSectionIDs: visibleSectionIDs
                    )
                        .navigationTitle("Sections")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    model.isSectionsWindowOpen = false
                                    dismissWindow(id: "sections-window")
                                } label: {
                                    Label("Return to Text", systemImage: "arrow.left.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        visibleSectionIDs = nil
                                    } label: {
                                        Label("Show All Sections", systemImage: "rectangle.stack")
                                    }
                                    Button {
                                        if visibleSectionIDs == nil {
                                            visibleSectionIDs = Set(sections.map(\.id))
                                        }
                                        showingSectionFilterSheet = true
                                    } label: {
                                        Label("Custom Selection…", systemImage: "checklist")
                                    }
                                } label: {
                                    Label(filterButtonLabel, systemImage: visibleSectionIDs == nil ? "rectangle.stack" : "line.3.horizontal.decrease.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .help("Choose which sections to display")
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    overviewOrder = overviewOrder == .row ? .column : .row
                                } label: {
                                    Label(overviewOrder.label, systemImage: overviewOrder.systemImage)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .help("Switch section ordering")
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    saveCurrentOrder()
                                } label: {
                                    Label("Save Reorder", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!hasPendingReorder)
                            }
                        }
                        .sheet(isPresented: $showingSectionFilterSheet) {
                            SectionFilterSheet(
                                sections: sections,
                                selection: Binding(
                                    get: { visibleSectionIDs ?? Set(sections.map(\.id)) },
                                    set: { visibleSectionIDs = $0 }
                                ),
                                onShowAll: { visibleSectionIDs = nil },
                                onDismiss: { showingSectionFilterSheet = false }
                            )
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
            pendingTextSyncTask?.cancel()
            pendingTextSyncTask = nil
        }
        .onChange(of: sections) { _, newSections in
            guard let projectID = currentProjectID,
                  let currentProject = model.projects.first(where: { $0.id == projectID }) else { return }

            if newSections == currentProject.sections {
                pendingTextSyncTask?.cancel()
            } else if isSectionOrderChange(newSections, comparedTo: currentProject.sections) {
                pendingTextSyncTask?.cancel()
                model.updateProjectSections(id: projectID, sections: newSections)
            } else {
                scheduleTextSync(for: projectID, sections: newSections)
            }
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

    private func scheduleTextSync(for projectID: UUID, sections newSections: [Section]) {
        pendingTextSyncTask?.cancel()
        pendingTextSyncTask = Task { @MainActor in
            defer { pendingTextSyncTask = nil }

            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            model.updateProjectSections(id: projectID, sections: newSections)
        }
    }

    private func isSectionOrderChange(_ newSections: [Section], comparedTo currentSections: [Section]) -> Bool {
        newSections.map(\.id) != currentSections.map(\.id)
    }
    
    private func saveCurrentOrder() {
        guard let projectID = currentProjectID else { return }
        pendingTextSyncTask?.cancel()
        pendingTextSyncTask = nil
        model.updateProjectSections(id: projectID, sections: sections)
        savedSectionOrder = sections.map(\.id)
        hasPendingReorder = false
    }
}

struct SectionsGridView: View {
    private let minimumCardWidth: CGFloat = 420
    private let gridSpacing: CGFloat = 24
    private let horizontalInsets: CGFloat = 48
    private let verticalInsets: CGFloat = 48
    private let estimatedCardHeight: CGFloat = 200
    
    @Binding var sections: [Section]
    @Binding var overviewOrder: SectionsOverviewOrder
    var visibleSectionIDs: Set<UUID>?
    @State private var draggedSectionID: UUID?
    @State private var expandedSectionIDs: Set<UUID> = []

    private var visibleIndexSet: [Int] {
        guard let visibleSectionIDs else { return Array(0..<sections.count) }
        return sections.indices.filter { visibleSectionIDs.contains(sections[$0].id) }
    }

    var body: some View {
        GeometryReader { proxy in
            let visibleIndices = visibleIndexSet
            if visibleIndices.isEmpty {
                ContentUnavailableView(
                    "No sections selected",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Use the filter menu in the toolbar to choose which sections to show.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let preferredRows = computedPreferredRows(for: proxy.size.height)
                let columnsCount = computedColumns(
                    for: proxy.size.width,
                    count: visibleIndices.count,
                    preferredRows: preferredRows
                )
                let gridItems = computedGridItems(columnsCount: columnsCount)
                let displayIndices = orderedIndices(indices: visibleIndices, columns: columnsCount)

                ScrollView {
                    LazyVGrid(columns: gridItems, spacing: gridSpacing) {
                        ForEach(displayIndices, id: \.self) { index in
                            sectionCard(at: index)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private func computedColumns(for width: CGFloat, count: Int, preferredRows: Int) -> Int {
        let availableWidth = max(width - horizontalInsets, minimumCardWidth)
        let columnWidth = minimumCardWidth + gridSpacing
        let maxColumnsByWidth = max(1, Int((availableWidth + gridSpacing) / columnWidth))

        if overviewOrder == .row {
            return maxColumnsByWidth
        }

        // In column mode, target vertical fill first, then clamp to available width.
        let neededColumnsForPreferredRows = max(1, Int(ceil(Double(max(count, 1)) / Double(max(preferredRows, 1)))))
        return min(maxColumnsByWidth, neededColumnsForPreferredRows)
    }

    private func computedGridItems(columnsCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: minimumCardWidth), spacing: gridSpacing),
            count: max(1, columnsCount)
        )
    }

    private func computedPreferredRows(for height: CGFloat) -> Int {
        let availableHeight = max(height - verticalInsets, estimatedCardHeight)
        return max(1, Int((availableHeight + gridSpacing) / (estimatedCardHeight + gridSpacing)))
    }

    @ViewBuilder
    private func sectionCard(at index: Int) -> some View {
        let section = sections[index]
        let isExpanded = expandedSectionIDs.contains(section.id)

        SectionsOverviewCard(
            index: index,
            section: $sections[index],
            isExpanded: isExpanded,
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

    private func orderedIndices(indices: [Int], columns: Int) -> [Int] {
        guard !indices.isEmpty else { return [] }
        if overviewOrder == .row {
            return indices
        }

        let count = indices.count
        let safeColumns = max(columns, 1)
        let rowCount = Int(ceil(Double(count) / Double(safeColumns)))
        let remainder = count % safeColumns
        let numFullColumns = remainder == 0 ? safeColumns : remainder

        var columnOffsets: [Int] = []
        columnOffsets.reserveCapacity(safeColumns)
        var runningOffset = 0
        for column in 0..<safeColumns {
            columnOffsets.append(runningOffset)
            runningOffset += column < numFullColumns ? rowCount : max(rowCount - 1, 0)
        }

        var result: [Int] = []
        result.reserveCapacity(count)
        for row in 0..<rowCount {
            for column in 0..<safeColumns {
                let columnLength = column < numFullColumns ? rowCount : rowCount - 1
                if row < columnLength {
                    let position = columnOffsets[column] + row
                    result.append(indices[position])
                }
            }
        }
        return result
    }
}

struct SectionFilterSheet: View {
    let sections: [Section]
    @Binding var selection: Set<UUID>
    var onShowAll: () -> Void
    var onDismiss: () -> Void

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
                        Label("Select All")
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
            .navigationTitle("Filter Sections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Show All") {
                        onShowAll()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func sectionPreview(for section: Section) -> String {
        let trimmed = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(Empty section)" }
        return String(trimmed.prefix(160))
    }
}

struct SectionsOverviewCard: View {
    let index: Int
    @Binding var section: Section
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDragStart: () -> NSItemProvider

    private let collapsedCardHeight: CGFloat = 190
    @State private var calculatedHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.3x3.fill")
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
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                Spacer()
            }

            TextKitView(
                text: $section.text,
                textColors: section.colors,
                textHighlights: section.highlights,
                textFontTypes: section.fontTypes,
                textFontSizes: section.fontSizes,
                textBoldStyles: section.boldStyles,
                textItalicStyles: section.italicStyles,
                textUnderlineStyles: section.underlineStyles,
                textStrikethroughStyles: section.strikethroughStyles,
                splitMode: false,
                snappedY: .constant(0),
                onSplit: { _ in },
                onAttach: { _ in },
                onSelectionChange: { _, _ in },
                calculatedHeight: $calculatedHeight
            )
            .frame(height: isExpanded ? calculatedHeight : 84)
            .clipped()
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
        .frame(height: isExpanded ? max(collapsedCardHeight, calculatedHeight + 96) : collapsedCardHeight)
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
}
