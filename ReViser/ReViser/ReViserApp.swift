//
//  ReViserApp.swift
//  ReViser
//
//  Created by Joey Tan on 4/2/26.
//

import SwiftUI

@main
struct ReViserApp: App {

    @State private var appModel = AppModel()

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
        
        // this is for the matrix section layout window (with all sections)
        WindowGroup(id: "sections-window") {
            SectionsWindowScene()
                .environment(appModel)
        }
        .windowStyle(.automatic)
        .windowResizability(.automatic)

        WindowGroup(id: "graveyard-window") {
            GraveyardWindowScene()
                .environment(appModel)
        }
        .windowStyle(.automatic)
        .windowResizability(.automatic)

        WindowGroup(id: "compare-window") {
            CompareDraftsView()
                .environment(appModel)
        }
        .windowStyle(.automatic)
        .windowResizability(.automatic)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

