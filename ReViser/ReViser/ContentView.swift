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

    var body: some View {
        HomeView()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
