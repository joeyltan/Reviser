import SwiftUI
import RadixUI

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var text: String = ""
    @State private var sections: [String] = []
    @State private var splitMode: Bool = false
    @State private var showToolbar: Bool = true
    @State private var hoverPosition: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    let projectID: UUID

    var body: some View {
        if let project = model.projects.first(where: { $0.id == projectID }) {
            HStack(spacing: 0) {
                // Left collapsible toolbar
                if showToolbar {
                    VStack(spacing: 16) {
                        Button(action: { splitMode.toggle() }) {
                            Image("scissors", bundle: .radixUI)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .foregroundColor(splitMode ? .blue : .gray)
                        }
                        .help("Toggle split mode")
                        
                        Spacer()
                    }
                    .frame(width: 60)
                    .padding()
                    .background(Color(white: 0.95))
                    .border(Color.gray.opacity(0.3), width: 1)
                }
                
                // Toggle toolbar button
                Button(action: { showToolbar.toggle() }) {
                    Image(systemName: showToolbar ? "chevron.left" : "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .frame(width: 30)
                .padding(.vertical)
                
                // Main content
                ScrollView {
                    GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("scroll")).minY)
                        }
                        .frame(height: 0)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text(project.title)
                            .font(.largeTitle)
                            .bold()
                        
                        ZStack(alignment: .topLeading) {
                            
                            if splitMode {
                                Color.clear
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear
                                                    .onAppear { textWidth = geo.size.width }
                                                    .onChange(of: geo.size.width) { _, newWidth in
                                                        textWidth = newWidth
                                                    }
                                            }
                                        )

                                
                                VStack(alignment: .leading, spacing: 24) {
                                    ForEach(sections.indices, id: \.self) { index in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("\(index + 1)")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            Text(sections[index])
                                                .font(.system(size: 25))
                                                .multilineTextAlignment(.leading)
                                                .frame(minHeight: 300)
                                                
                                        }
                                    }
                                }
                                // Text(text)
                                //     .font(.system(size: 25))
                                //     .multilineTextAlignment(.leading)
                                //     .frame(minHeight: 300)
                            } else {
                                // when not splitting into sections, show text editor
                                TextEditor(text: $text)
                                    .font(.system(size: 25))
                                    .multilineTextAlignment(.leading)
                                    .frame(minHeight: 300)
                            }
                            
                            if splitMode {
                                // Transparent hover tracking layer
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        if case .active(let location) = phase {
                                            hoverPosition = location.y
                                            print("hover y:", hoverPosition)
                                        }
                                    }
                                    .highPriorityGesture(
                                        // for splitting text on 2 tap
                                        SpatialTapGesture(count: 2)
                                            .onEnded { value in
                                                hoverPosition = value.location.y
                                                print("double tap hover pos", hoverPosition)
                                                splitText(at: hoverPosition)
                                            }
                                    )
                                    .simultaneousGesture(
                                        // for setting hover position on 1 click
                                        SpatialTapGesture(count: 1)
                                            .onEnded { value in
                                                hoverPosition = value.location.y
                                                print("tap hover pos", hoverPosition)
                                            }
                                    )
//                                     .gesture(
//                                         SpatialTapGesture()
//                                             .onEnded { value in
//                                                 hoverPosition = value.location.y
// //                                                print("this tap y:", hoverPosition)
//                                             }
//                                     )
                                
                                // dashed line
                                Path { path in
                                    path.move(to: CGPoint(x: -10, y: hoverPosition))
                                    path.addLine(to: CGPoint(x: 1020, y: hoverPosition)) // large width
                                }
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .foregroundColor(.gray)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.vertical, 36)
                    .padding(.horizontal, 80)
                }
            }
            .onAppear {
//                print("proj text", project.text)
                text = project.text
                sections = [project.text]
            }
            .onChange(of: text) { _, newValue in
                model.updateProjectText(id: projectID, text: newValue)
            }
            .navigationTitle(project.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Project not found", systemImage: "doc", description: Text("The selected project could not be loaded."))
                .padding()
        }
    }
    
    func splitText(at y: CGFloat) {
        let adjustedY = y + scrollOffset

        // Make sure we have at least one section
        if sections.isEmpty {
            sections = [text]
        }

        var cumulativeY: CGFloat = 0
        var targetIndex: Int = 0
        var localY: CGFloat = adjustedY

        // Find which section the cursor is over
        for (idx, section) in sections.enumerated() {
            let font = UIFont.systemFont(ofSize: 25)
            let bounding = NSString(string: section).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil
            )

            let sectionHeight = bounding.height + 24 // include VStack spacing
            if cumulativeY + sectionHeight >= adjustedY {
                targetIndex = idx
                localY = adjustedY - cumulativeY
                break
            }
            cumulativeY += sectionHeight

            if idx == sections.count - 1 {
                targetIndex = idx
                localY = sectionHeight
            }
        }

        let target = sections[targetIndex]
        let font = UIFont.systemFont(ofSize: 25)

        // precise line mapping
        let textStorage = NSTextStorage(string: target)
        let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: target.count))

        // Find the character index corresponding to the hover Y
        var lineY: CGFloat = 0
        var charIndex: Int = 0
        let numberOfGlyphs = layoutManager.numberOfGlyphs
        var glyphIndex = 0

        while glyphIndex < numberOfGlyphs {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

            if localY < lineY + lineRect.height {
                // cursor is in this line
                let ratio = (localY - lineY) / lineRect.height
                charIndex = lineRange.location + Int(CGFloat(lineRange.length) * ratio)
                break
            }

            lineY += lineRect.height
            glyphIndex = lineRange.location + lineRange.length
        }
        
        print("line y is", lineY)

        let safeIndex = min(max(charIndex, 0), target.count)
        let splitIdx = target.index(target.startIndex, offsetBy: safeIndex)

        let firstPart = String(target[..<splitIdx])
        let secondPart = String(target[splitIdx...])

        var newSections: [String] = []
        newSections.append(contentsOf: sections[..<targetIndex])

        if !firstPart.isEmpty { newSections.append(firstPart) }
        if !secondPart.isEmpty { newSections.append(secondPart) }

        if firstPart.isEmpty && secondPart.isEmpty {
            newSections.append("")
        }

        if targetIndex + 1 < sections.count {
            newSections.append(contentsOf: sections[(targetIndex + 1)...])
        }

        sections = newSections
        text = sections.joined()
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    let model = AppModel()
    let p = AppModel.Project(id: UUID(), title: "Sample", sourceURL: URL(fileURLWithPath: "/tmp/sample.txt"), createdAt: .now, lastModified: .now, text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
    model.projects = [p]
    return NavigationStack {
        ProjectDetailView(projectID: p.id)
            .environment(model)
    }
}

