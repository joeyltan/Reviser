//
//  ContentView.swift
//  ReViser
//
//  Created by Joey Tan on 4/2/26.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            HomeView()
//                .navigationTitle("Projects")
        }
        .navigationDestination(for: UUID.self) { id in
            ProjectDetailView(projectID: id)
                .environment(appModel)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
