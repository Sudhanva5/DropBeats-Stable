import SwiftUI

struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    let isSearching: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search YouTube Music...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
} 