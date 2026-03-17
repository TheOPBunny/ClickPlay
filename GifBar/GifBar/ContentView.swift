//
//  ContentView.swift
//  GifBar
//
//  Created by Hassan Zahid on 10/12/25.
//

import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""
    func searchPressed() {
        let API_KEY = "AIzaSyBPdqZ6-l3RuB-al58IjJ8813JtEjgbJJU"
        let urlString = "https://tenor.googleapis.com/v2/search?q=\(searchText)&key=\(API_KEY)&limit=8"
        print(urlString)
        
        guard let url = URL(string: urlString) else 
    }
    var body: some View {
        VStack {
           
            VStack {
                Text("My GIF Searcher")
                    .font(.largeTitle)
                TextField("Search", text: $searchText)
                // A horizontal stack for a label and a value
                
                Text(searchText)
                
                Button("Search") {
                    print("Searching \(searchText)")
                }
                HStack {
                    Text("Searching for:")
                    Text("funny cats") // This is still just placeholder text
                }
            }        }
        .padding()
    }
}

#Preview {
    ContentView()
}
