import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: result.type.iconName)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(result.title)
                    .fontWeight(.medium)
                Text(result.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Text("↵")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - ResultType Extensions
extension SearchResult.ResultType {
    var iconName: String {
        switch self {
        case .song: return "music.note"
        case .album: return "square.stack"
        case .playlist: return "music.note.list"
        }
    }
} 