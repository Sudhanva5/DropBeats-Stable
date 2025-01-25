import SwiftUI

struct SearchResultsList: View {
    let sections: [SearchSection]
    let selectedIndex: Int
    let showRecent: Bool
    let onSelect: (SearchResult) -> Void
    let isKeyboardNavigation: Bool
    let isNavigatingUp: Bool
    
    private var flattenedResults: [SearchResult] {
        sections.flatMap { $0.results }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Only use spacer for search results
                    if !isKeyboardNavigation {
                        Spacer(minLength: 0)
                    }
                    
                    if showRecent {
                        Text("Recently Played")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }
                    
                    ForEach(sections) { section in
                        if !section.results.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                if !showRecent {
                                    Text(section.title)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 4)
                                }
                                
                                ForEach(section.results) { result in
                                    let index = flattenedResults.firstIndex(where: { $0.id == result.id }) ?? 0
                                    SearchResultRow(result: result, isSelected: index == selectedIndex)
                                        .id(index)
                                        .onTapGesture {
                                            onSelect(result)
                                        }
                                }
                                
                                if !showRecent {
                                    Divider()
                                        .padding(.vertical, 12)
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
                .frame(maxHeight: .infinity, alignment: isKeyboardNavigation ? .top : .bottom)
                .padding(.bottom, 40)
            }
            .onChange(of: selectedIndex) { newIndex in
                // Only scroll if we have results
                if !flattenedResults.isEmpty {
                    // Use different scroll behavior for keyboard navigation vs search
                    if isKeyboardNavigation {
                        // Natural scrolling for keyboard navigation
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newIndex, anchor: nil)
                        }
                    } else {
                        // Bottom anchoring only for search results
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
} 
