import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    
    var body: some View {
        // CUSTOMIZE: Horizontal spacing between elements (album art, text, enter key)
        HStack(spacing: 12) {  // Change '12' to adjust space between row elements
            // Album Art with Shadow
            if let thumbnailUrl = result.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // CUSTOMIZE: Album art size
                            .frame(width: 40, height: 40)  // Change size of album art
                            .cornerRadius(4)               // Change corner radius
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)  // Customize shadow
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
            
            // CUSTOMIZE: Text spacing
            VStack(alignment: .leading) {  // Add spacing: parameter to adjust space between title and artist
                Text(result.title)
                    .fontWeight(.medium)
                Text(result.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Text("↵ ")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        // CUSTOMIZE: Row internal padding
        .padding(.vertical, 8)      // Space above/below content inside row
        .padding(.horizontal, 8)    // Space left/right of content inside row
        .background(
            Group {
                if isSelected {
                    VisualEffectView(material: .selection, blendingMode: .withinWindow)
                }
            }
        )
        .cornerRadius(6)
        // CUSTOMIZE: Row external padding
        .padding(.vertical, 4)      // Space between rows
        .contentShape(Rectangle())
    }
    
    private var fallbackIcon: some View {
        Image(systemName: result.type.iconName)
            .foregroundColor(.secondary)
            // CUSTOMIZE: Fallback icon size (should match album art size)
            .frame(width: 40, height: 40)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
    }
} 
