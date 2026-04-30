#if DEBUG
import Foundation

enum UITestSupport {
    static let seedProjectFlag = "-UITestSeedProject"
    static let seededProjectTitle = "UITestProject"
    static let seededSectionText =
        "This is the seeded UI test project text. It has multiple sentences. Lorem ipsum dolor sit amet."

    static var isSeedingRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(seedProjectFlag)
    }

    @MainActor
    static func seedIfNeeded(_ model: AppModel) {
        guard isSeedingRequested else { return }
        let section = Section(id: UUID(), text: seededSectionText)
        let project = AppModel.Project(
            id: UUID(),
            title: seededProjectTitle,
            sourceURL: URL(fileURLWithPath: "/dev/null/\(seededProjectTitle)"),
            createdAt: .now,
            lastModified: .now,
            text: seededSectionText,
            sections: [section]
        )
        model.projects = [project]
    }
}
#endif
