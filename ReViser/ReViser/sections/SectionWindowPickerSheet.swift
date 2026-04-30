import SwiftUI

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
