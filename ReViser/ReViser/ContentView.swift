//
//  ContentView.swift
//  ReViser
//

import SwiftUI

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
