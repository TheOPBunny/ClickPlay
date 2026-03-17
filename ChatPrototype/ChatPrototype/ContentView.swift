//
//  ContentView.swift
//  ChatPrototype
//
//  Created by Hassan Zahid on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("What’s up, homie")
                .padding()
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 48))

            Text("Nothing much")
                .padding()
                .background(Color.teal, in: RoundedRectangle(cornerRadius: 48))

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
