import SwiftUI

struct SearchResultsList: View {
    let sections: [SearchSection]
    let selectedIndex: Int
    let showRecent: Bool
    let onSelect: (SearchResult) -> Void
    
    private var flattenedResults: [SearchResult] {
        sections.flatMap { $0.results }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if showRecent {
                    Text("Recently Played")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                
                ForEach(sections) { section in
                    if !section.results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            if !showRecent {
                                Text(section.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                            }
                            
                            ForEach(section.results) { result in
                                let index = flattenedResults.firstIndex(where: { $0.id == result.id }) ?? 0
                                SearchResultRow(result: result, isSelected: index == selectedIndex)
                                    .onTapGesture {
                                        onSelect(result)
                                    }
                            }
                            
                            if !showRecent {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                if sections.isEmpty && showRecent {
                    Text("No recently played songs")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
    }
} 