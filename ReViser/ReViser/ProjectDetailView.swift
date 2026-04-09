import SwiftUI
import RadixUI
import UIKit

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var sections: [Section] = []
    @State private var textViews: [UUID: UITextView] = [:]
    @State private var snappedY: CGFloat = 0
    @State private var showToolbar: Bool = true
    @State private var splitMode: Bool = false

    @State private var activeSectionID: UUID?
    @State private var caretIndexBySection: [UUID: Int] = [:]
    @State private var sectionHeights: [UUID: CGFloat] = [:]

    let projectID: UUID

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectID }) {

            HStack(spacing: 0) {

                // Toolbar
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
                        Spacer()
                    }
                    .frame(width: 60)
                    .padding()
                    .background(Color(white: 0.95))
                }

                Button {
                    showToolbar.toggle()
                } label: {
                    Image(systemName: showToolbar ? "chevron.left" : "chevron.right")
                }
                .frame(width: 30)

                // Main TextKit View
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
            .onAppear {
                sections = project.sections.isEmpty
                    ? [Section(id: UUID(), text: "")]
                    : project.sections
            }
            .onChange(of: sections) { _, newSections in
                model.updateProjectSections(id: projectID, sections: newSections)
            }

        } else {
            Text("Project not found")
        }
    }
    
    @ViewBuilder
    func sectionView(section: Section, index: Int) -> some View {
//        let index = sections.firstIndex(where: { $0.id == section.id }) ?? 0
        Text("\(index + 1)")
            .font(.caption)
            .foregroundColor(.gray)

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
                    ),
        )
        .multilineTextAlignment(.leading)
        .frame(height: sectionHeights[section.id] ?? 100)
        .frame(maxWidth: .infinity)// temporarily including this because I can't figure out a better wayy
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



//import SwiftUI
//import RadixUI
//
//struct ProjectDetailView: View {
//    @Environment(AppModel.self) private var model
//    @State private var text: String = ""
//    @State private var sections: [String] = []
//    @State private var splitMode: Bool = false
//    @State private var showToolbar: Bool = true
//    @State private var hoverPosition: CGFloat = 0
//    @State private var scrollOffset: CGFloat = 0
//    @State private var textWidth: CGFloat = 0
//    @State private var snappedY: CGFloat = 0
//    let projectID: UUID
//
//    var body: some View {
//        if let project = model.projects.first(where: { $0.id == projectID }) {
//            HStack(spacing: 0) {
//                // Left collapsible toolbar
//                if showToolbar {
//                    VStack(spacing: 16) {
//                        Button(action: { splitMode.toggle() }) {
//                            Image("scissors", bundle: .radixUI)
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(width: 32, height: 32)
//                                .foregroundColor(splitMode ? .blue : .gray)
//                        }
//                        .help("Toggle split mode")
//                        
//                        Spacer()
//                    }
//                    .frame(width: 60)
//                    .padding()
//                    .background(Color(white: 0.95))
//                    .border(Color.gray.opacity(0.3), width: 1)
//                }
//                
//                // Toggle toolbar button
//                Button(action: { showToolbar.toggle() }) {
//                    Image(systemName: showToolbar ? "chevron.left" : "chevron.right")
//                        .font(.system(size: 14))
//                        .foregroundColor(.gray)
//                }
//                .frame(width: 30)
//                .padding(.vertical)
//                
//                // Main content
//                ScrollView {
//                    GeometryReader { geo in
//                            Color.clear
//                                .preference(key: ScrollOffsetKey.self,
//                                            value: geo.frame(in: .named("scroll")).minY)
//                        }
//                        .frame(height: 0)
//                    
//                    VStack(alignment: .leading, spacing: 16) {
//                        Text(project.title)
//                            .font(.largeTitle)
//                            .bold()
//                        
//                        ZStack(alignment: .topLeading) {
//                            
//                            if splitMode {
//                                Color.clear
//                                        .background(
//                                            GeometryReader { geo in
//                                                Color.clear
//                                                    .onAppear { textWidth = geo.size.width }
//                                                    .onChange(of: geo.size.width) { _, newWidth in
//                                                        textWidth = newWidth
//                                                    }
//                                            }
//                                        )
//
//                                
//                                VStack(alignment: .leading, spacing: 24) {
//                                    ForEach(sections.indices, id: \.self) { index in
//                                        VStack(alignment: .leading, spacing: 8) {
//                                            Text("\(index + 1)")
//                                                .font(.caption)
//                                                .foregroundColor(.gray)
//
//                                            Text(sections[index])
//                                                .font(.system(size: 25))
//                                                .multilineTextAlignment(.leading)
//                                                .frame(minHeight: 300)
//                                                
//                                        }
//                                    }
//                                }
//                                // Text(text)
//                                //     .font(.system(size: 25))
//                                //     .multilineTextAlignment(.leading)
//                                //     .frame(minHeight: 300)
//                            } else {
//                                // when not splitting into sections, show text editor
//                                TextEditor(text: $text)
//                                    .font(.system(size: 25))
//                                    .multilineTextAlignment(.leading)
//                                    .frame(minHeight: 300)
//                            }
//                            
//                            if splitMode {
//                                // Transparent hover tracking layer
//                                Color.clear
//                                    .contentShape(Rectangle())
//                                    .onContinuousHover { phase in
//                                        if case .active(let location) = phase {
//                                            hoverPosition = location.y
//                                            snappedY = snapToLineY(globalY: location.y)
//                                            print("hover y:", hoverPosition)
//                                        }
//                                    }
//                                    .highPriorityGesture(
//                                        // for splitting text on 2 tap
//                                        SpatialTapGesture(count: 2)
//                                            .onEnded { value in
//                                                hoverPosition = value.location.y
//                                                snappedY = snapToLineY(globalY: hoverPosition)
//                                                print("double tap hover pos", hoverPosition)
//                                                print("snapped y", snappedY)
//                                                splitText(at: snappedY)
//                                            }
//                                    )
//                                    .simultaneousGesture(
//                                        // for setting hover position on 1 click
//                                        SpatialTapGesture(count: 1)
//                                            .onEnded { value in
//                                                hoverPosition = value.location.y
//                                                snappedY = snapToLineY(globalY: hoverPosition)
//                                                print("tap hover pos", hoverPosition)
//                                                print("tap snapped Y", snappedY)
//                                            }
//                                    )
////                                     .gesture(
////                                         SpatialTapGesture()
////                                             .onEnded { value in
////                                                 hoverPosition = value.location.y
//// //                                                print("this tap y:", hoverPosition)
////                                             }
////                                     )
//                                
//                                // dashed line
//                                Path { path in
////                                    path.move(to: CGPoint(x: -10, y: hoverPosition))
////                                    path.addLine(to: CGPoint(x: 1020, y: hoverPosition)) // large width
//                                    path.move(to: CGPoint(x: -10, y: snappedY))
//                                    path.addLine(to: CGPoint(x: 1020, y: snappedY))
//                                }
//                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
//                                .foregroundColor(.gray)
//                                .allowsHitTesting(false)
//                            }
//                        }
//                    }
//                    .padding(.vertical, 36)
//                    .padding(.horizontal, 80)
//                }
//                .coordinateSpace(name: "scroll")
//                .onPreferenceChange(ScrollOffsetKey.self) { value in
//                    scrollOffset = -value
//                }
//            }
//            .onAppear {
////                print("proj text", project.text)
//                text = project.text
//                sections = [project.text]
//            }
//            .onChange(of: text) { _, newValue in
//                model.updateProjectText(id: projectID, text: newValue)
//            }
//            .navigationTitle(project.title)
//            .navigationBarTitleDisplayMode(.inline)
//        } else {
//            ContentUnavailableView("Project not found", systemImage: "doc", description: Text("The selected project could not be loaded."))
//                .padding()
//        }
//    }
//    
//    func splitText(at y: CGFloat) {
//        let adjustedY = y + scrollOffset
//
//        // Make sure we have at least one section
//        if sections.isEmpty {
//            sections = [text]
//        }
//
//        var cumulativeY: CGFloat = 0
//        var targetIndex: Int = 0
//        var localY: CGFloat = adjustedY
//
//        // Find which section the cursor is over
//        for (idx, section) in sections.enumerated() {
//            let font = UIFont.systemFont(ofSize: 25)
//            let bounding = NSString(string: section).boundingRect(
//                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
//                options: [.usesLineFragmentOrigin],
//                attributes: [.font: font],
//                context: nil
//            )
//
//            let sectionHeight = bounding.height + 8 + 24
//            if cumulativeY + sectionHeight >= adjustedY {
//                targetIndex = idx
//                localY = adjustedY - cumulativeY
//                break
//            }
//            cumulativeY += sectionHeight
//
//            if idx == sections.count - 1 {
//                targetIndex = idx
//                localY = sectionHeight
//            }
//        }
//
//        let target = sections[targetIndex]
//        let font = UIFont.systemFont(ofSize: 25)
//
//        // precise line mapping
//        let textStorage = NSTextStorage(string: target)
//        let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
//        textContainer.lineFragmentPadding = 0
//        let layoutManager = NSLayoutManager()
//
//        layoutManager.addTextContainer(textContainer)
//        textStorage.addLayoutManager(layoutManager)
//        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: target.count))
//
//        // Find the character index corresponding to the hover Y
//        var lineY: CGFloat = 0
//        var charIndex: Int = 0
//        let numberOfGlyphs = layoutManager.numberOfGlyphs
//        var glyphIndex = 0
//
//        while glyphIndex < numberOfGlyphs {
//            var lineRange = NSRange()
//            let lineRect = layoutManager.lineFragmentUsedRect(
//                forGlyphAt: glyphIndex,
//                effectiveRange: &lineRange
//            )
//
//            if localY < lineY + lineRect.height {
//                charIndex = lineRange.location
//                break
//            }
//
//            lineY += lineRect.height
//            glyphIndex = lineRange.location + lineRange.length
//        }
//        
//        print("line y is", lineY)
//
//        let safeIndex = min(max(charIndex, 0), target.count)
//        let splitIdx = target.index(target.startIndex, offsetBy: safeIndex)
//
//        let firstPart = String(target[..<splitIdx])
//        let secondPart = String(target[splitIdx...])
//
//        var newSections: [String] = []
//        newSections.append(contentsOf: sections[..<targetIndex])
//
//        if !firstPart.isEmpty { newSections.append(firstPart) }
//        if !secondPart.isEmpty { newSections.append(secondPart) }
//
//        if firstPart.isEmpty && secondPart.isEmpty {
//            newSections.append("")
//        }
//
//        if targetIndex + 1 < sections.count {
//            newSections.append(contentsOf: sections[(targetIndex + 1)...])
//        }
//
//        sections = newSections
//        text = sections.joined()
//    }
//    
//    func snapToLineY(globalY: CGFloat) -> CGFloat {
//        let adjustedY = globalY + scrollOffset
//
//        var cumulativeY: CGFloat = 0
//
//        for section in sections {
//            let font = UIFont.systemFont(ofSize: 25)
//
//            let textStorage = NSTextStorage(string: section)
//            let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
//            textContainer.lineFragmentPadding = 0
//            let layoutManager = NSLayoutManager()
//
//            layoutManager.addTextContainer(textContainer)
//            textStorage.addLayoutManager(layoutManager)
//            textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: section.count))
//
//            var glyphIndex = 0
//            var lineY: CGFloat = 0
//
//            while glyphIndex < layoutManager.numberOfGlyphs {
//                var lineRange = NSRange()
//                let lineRect = layoutManager.lineFragmentUsedRect(
//                    forGlyphAt: glyphIndex,
//                    effectiveRange: &lineRange
//                )
//
//                let globalLineTop = cumulativeY + lineY
//                let globalLineMid = globalLineTop + lineRect.height / 2
//
//                if adjustedY < globalLineTop + lineRect.height {
//                    // snap to nearest boundary
//                    if adjustedY < globalLineMid {
//                        return globalLineTop - scrollOffset
//                    } else {
//                        return globalLineTop + lineRect.height - scrollOffset
//                    }
//                }
//
//                lineY += lineRect.height
//                glyphIndex = lineRange.location + lineRange.length
//            }
//
//            cumulativeY += lineY + 8 + 24
//        }
//
//        return globalY
//    }
//}
//
//struct ScrollOffsetKey: PreferenceKey {
//    static var defaultValue: CGFloat = 0
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = nextValue()
//    }
//}
//
//#Preview {
//    let model = AppModel()
//    let p = AppModel.Project(id: UUID(), title: "Sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), createdAt: .now, lastModified: .now, text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
//    model.projects = [p]
//    return NavigationStack {
//        ProjectDetailView(projectID: p.id)
//            .environment(model)
//    }
//}
//

