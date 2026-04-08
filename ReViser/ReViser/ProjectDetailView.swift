import SwiftUI
import RadixUI

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var text: String = ""
    @State private var splitMode: Bool = false
    @State private var showToolbar: Bool = true
    @State private var hoverPosition: CGFloat = 0
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
                    VStack(alignment: .leading, spacing: 16) {
                        Text(project.title)
                            .font(.largeTitle)
                            .bold()
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $text)
                                .font(.system(size: 25))
                                .multilineTextAlignment(.leading)
                                .frame(minHeight: 300)

                            // Transparent hover tracking layer
                            if splitMode {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        if case .active(let location) = phase {
                                            hoverPosition = location.y
                                            print("hover y:", hoverPosition)
                                        }
                                    }
                                    .gesture(
                                        SpatialTapGesture()
                                            .onEnded { value in
                                                hoverPosition = value.location.y
                                                print("this tap y:", hoverPosition)
                                            }
                                    )
                            }

                            if splitMode {
                                Rectangle()
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .foregroundColor(.gray)
                                    .frame(height: 1)
                                    .offset(y: hoverPosition)
                                    .allowsHitTesting(false)
                            }
                        }
                        
                        // ZStack {
                        //     TextEditor(text: $text)
                        //         .font(.system(size: 25))
                        //         .multilineTextAlignment(.leading)
                        //         .frame(minHeight: 300)
                        //         .contentShape(Rectangle())
                            
                        // }
                    }
                    .padding(.vertical, 36)
                    .padding(.horizontal, 80)
                }
//                .overlay(alignment: .topLeading) {
//                    if splitMode {
//                        Rectangle()
//                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
//                            .foregroundColor(.gray)
//                            .frame(height: 1)
//                            .offset(y: hoverPosition)
//                            .allowsHitTesting(false)
//                    }
//                }
            }
            .onAppear {
//                print("proj text", project.text)
                text = project.text
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
