import SwiftUI
import RadixUI
import UIKit

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

    @State private var activeSectionID: UUID?
    @State private var caretIndexBySection: [UUID: Int] = [:]
    @State private var sectionHeights: [UUID: CGFloat] = [:]
    @State private var visibleActionSectionIDs: Set<UUID> = []

    let projectID: UUID

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectID }) {
            HStack(spacing: 0) {
                toolbarView
                toggleButton
                mainContentView(project: project)
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
    
    @ViewBuilder
    func sectionView(section: Section, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
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

        if activeSectionID == id {
            activeSectionID = sections.first?.id
        }

        if sections.isEmpty {
            let newSection = Section(id: UUID(), text: "")
            sections = [newSection]
            activeSectionID = newSection.id
        }
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
}

