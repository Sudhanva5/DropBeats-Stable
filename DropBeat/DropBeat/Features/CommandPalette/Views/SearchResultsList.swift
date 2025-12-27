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
                        // DESIGN: Section header - "Recently Played"
                        Text("Recently Played")
                            // DESIGN: Header font size
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // DESIGN: Header padding
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }
                    
                    ForEach(sections) { section in
                        if !section.results.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                if !showRecent {
                                    // DESIGN: Search result section titles (Songs, Videos, etc)
                                    Text(section.title)
                                        // DESIGN: Section title font size
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        // DESIGN: Section title padding
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 4)
                                }

                                ForEach(Array(section.results.enumerated()), id: \.offset) { sectionIndex, result in
                                    let globalIndex = flattenedResults.firstIndex(where: { $0.id == result.id }) ?? 0
                                    // DESIGN: Individual result row - customize in SearchResultRow.swift
                                    SearchResultRow(result: result, isSelected: globalIndex == selectedIndex)
                                        // Use unique ID combining section and result to prevent collisions
                                        .id("\(section.id)-\(result.id)")
                                        .onTapGesture {
                                            onSelect(result)
                                        }
                                }

                                if !showRecent {
                                    // DESIGN: Divider between sections - adjust padding
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
                if !flattenedResults.isEmpty && newIndex < flattenedResults.count {
                    // Find the section and result for this index
                    let selectedResult = flattenedResults[newIndex]
                    if let section = sections.first(where: { $0.results.contains(where: { $0.id == selectedResult.id }) }) {
                        let scrollId = "\(section.id)-\(selectedResult.id)"

                        // Use different scroll behavior for keyboard navigation vs search
                        if isKeyboardNavigation {
                            // Natural scrolling for keyboard navigation
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(scrollId, anchor: nil)
                            }
                        } else {
                            // Bottom anchoring only for search results
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(scrollId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
} 
