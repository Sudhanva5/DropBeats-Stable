import SwiftUI

struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    let isSearching: Bool

    var body: some View {
        HStack {
            // DESIGN: Search icon - adjust size and color
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                // DESIGN: Icon size
                .font(.system(size: 14, weight: .medium))

            // DESIGN: Search text input field
            TextField("Search in youtube music...", text: $searchText)
                .textFieldStyle(.plain)
                // DESIGN: Input text size
                .font(.title3)
                // DESIGN: Horizontal padding inside field
                .padding(.horizontal, 4)
                .focused($isFocused) // DESIGN: Focus state binding
                // Add visual indicator that field is ready for input
                .onChange(of: isFocused) { focused in
                    if focused {
                        print("🎯 [palette] SearchField now FOCUSED")
                    } else {
                        print("🎯 [palette] SearchField LOST focus")
                    }
                }

            if isSearching {
                // DESIGN: Loading spinner - adjust size with controlSize
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
        }
        // DESIGN: Search field padding
        .padding()
        .overlay(
            // DESIGN: Bottom border only - for top/left/right border change VStack alignment
            VStack {
                Spacer()
                // DESIGN: Bottom border - adjust height (thickness) and opacity
                Rectangle()
                    .frame(height: 0.6)  // DESIGN: Border thickness
                    .foregroundColor(Color.primary.opacity(0.05))  // DESIGN: Border color and opacity
            }
            , alignment: .bottom
        )
        
        .onAppear {
            // Ensure field appears ready for input
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommandPaletteWillShow"))) { _ in
            // When palette is about to show, make sure the input field is focused
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
} 
