//
//  ContentView.swift
//  test
//
//  Created by Hassan Zahid on 10/12/25.
//

import SwiftUI

let x: Float = 4

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("\(x)")
        }
        .padding()
        .onAppear {
            print(x)
        }
    }
}

#Preview {
    ContentView()
}
