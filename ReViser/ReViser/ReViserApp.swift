//
//  ReViserApp.swift
//  ReViser
//

import SwiftUI

@main
struct ReViserApp: App {

    @State private var appModel: AppModel = {
        let model = AppModel()
        #if DEBUG
        UITestSupport.seedIfNeeded(model) // for testing purposes
        #endif
        return model
    }()

    var body: some Scene {
        WindowGroup(id: "main-window") {
            NavigationStack {
                ContentView()
            }
            .environment(appModel)
        }
        
        // this is for individual section windows (currently button right under section number)
        // these can move at will - maybe think about how they can be also organized
        WindowGroup(id: "section-window", for: UUID.self) { $sectionID in
            if let sectionID {
                SectionWindowScene(sectionID: sectionID)
                    .environment(appModel)
            }
        }
        .windowStyle(.automatic)
        .windowResizability(.automatic)
        .defaultWindowPlacement { _, context in
            let sectionWindows = context.windows.filter { $0.id == "section-window" }
            let existingSectionWindows = sectionWindows.count
            let columns = 3
            let row = existingSectionWindows / columns

            guard let previousSectionWindow = sectionWindows.last else {
                if appModel.elevateSectionWindowsForBulkOpen,
                   let mainWindow = context.windows.first(where: { $0.id == "main-window" }) {
                    return WindowPlacement(.above(mainWindow), size3D: nil)
                }
                return WindowPlacement(size3D: nil)
            }

            if existingSectionWindows == 0 {
                if appModel.elevateSectionWindowsForBulkOpen,
                   let mainWindow = context.windows.first(where: { $0.id == "main-window" }) {
                    return WindowPlacement(.above(mainWindow), size3D: nil)
                }
                return WindowPlacement(size3D: nil)
            }

            // First row builds left-to-right.
            if row == 0 {
                return WindowPlacement(.trailing(previousSectionWindow), size3D: nil)
            }

            // Subsequent rows anchor to the same column above to reduce diagonal drift.
            let anchorIndex = max(0, existingSectionWindows - columns)
            let anchorWindow = sectionWindows[anchorIndex]
            return WindowPlacement(.below(anchorWindow), size3D: nil)
        }
        
        // this is for the matrix section layout window (with all sections)
        WindowGroup(id: "sections-window") {
            SectionsWindowScene()
                .environment(appModel)
        }
        .defaultSize(CGSize(width: 1800, height: 1050))
        .windowStyle(.automatic)
        .windowResizability(.automatic)

        WindowGroup(id: "graveyard-window", for: UUID.self) { $projectID in
            if let projectID {
                GraveyardWindowScene(projectID: projectID)
                    .environment(appModel)
            }
        }
        .windowStyle(.automatic)
        .windowResizability(.automatic)

        WindowGroup(id: "compare-window") {
            CompareDraftsView()
                .environment(appModel)
        }
        .defaultSize(CGSize(width: 1500, height: 1000))
        .windowStyle(.automatic)
        .windowResizability(.automatic)

    }
}

