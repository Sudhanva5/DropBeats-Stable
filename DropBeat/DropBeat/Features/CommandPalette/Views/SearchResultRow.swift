import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    
    var body: some View {
        // DESIGN: Horizontal spacing between elements (album art, text, enter key)
        HStack(spacing: 12) {  // DESIGN: Adjust to change space between row elements
            // DESIGN: Album Art with Shadow
            if let thumbnailUrl = result.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // DESIGN: Album art dimensions - adjust width and height
                            .frame(width: 40, height: 40)
                            // DESIGN: Album art corner radius
                            .cornerRadius(4)
                            // DESIGN: Album art shadow - adjust color opacity, blur radius, and offset
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    case .failure(_):
                        fallbackIcon
                    case .empty:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }

            // DESIGN: Title and artist text section
            VStack(alignment: .leading, spacing: 2) {  // DESIGN: Adjust spacing between title and artist
                // DESIGN: Result title styling
                Text(result.title)
                    .fontWeight(.medium)
                // DESIGN: Artist name styling
                Text(result.artist)
                    // DESIGN: Artist text font size
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                // DESIGN: Enter key indicator for selected item
                Text("↵ ")
                    .foregroundColor(.secondary)
                    // DESIGN: Enter key icon size
                    .font(.subheadline)
            }
        }
        // DESIGN: Row internal padding - space inside the row
        .padding(.vertical, 8)      // DESIGN: Vertical padding inside row
        .padding(.horizontal, 8)    // DESIGN: Horizontal padding inside row
        .background(
            Group {
                if isSelected {
                    // DESIGN: Selected row background - adjust color and opacity
                    Color(.systemGray)
                        .opacity(0.3)
                } else {
                    Color.clear
                }
            }
        )
        // DESIGN: Row background corner radius
        .cornerRadius(6)
        // DESIGN: Row external padding - space between rows
        .padding(.vertical, 4)      // DESIGN: Space above/below each row
        .contentShape(Rectangle())
    }
    
    private var fallbackIcon: some View {
        Image(systemName: result.type.iconName)
            .foregroundColor(.secondary)
            // DESIGN: Fallback icon size (should match album art dimensions)
            .frame(width: 40, height: 40)
            // DESIGN: Fallback icon background color opacity
            .background(Color.secondary.opacity(0.1))
            // DESIGN: Fallback icon corner radius (should match album art)
            .cornerRadius(4)
    }
} 
