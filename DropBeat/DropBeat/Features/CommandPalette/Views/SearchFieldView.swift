import SwiftUI

struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    let isSearching: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search in youtube music...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 4)
                .focused($isFocused)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
} 
