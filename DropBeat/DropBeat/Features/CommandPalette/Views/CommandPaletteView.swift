import SwiftUI

struct CommandPaletteView: View {
    @State private var state = CommandPaletteState.shared
    @FocusState private var isFocused: Bool
    @State private var selectedIndex = 0
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchError: SearchError?
    @State private var playbackError: (error: String, url: String)?
    @State private var isKeyboardNavigation = false
    @State private var isNavigatingUp = false
    
    @ObservedObject private var playerManager = MusicPlayerManager.shared

    private var recentlyPlayedSection: SearchSection {
        let recentResults = playerManager.recentTracks.compactMap { track -> SearchResult? in
            // Only create search results for tracks with valid IDs
            guard let id = track.id else { return nil }
            return SearchResult(
                id: id,
                title: track.title,
                artist: track.artist,
                type: .song,
                thumbnailUrl: track.albumArt
            )
        }
        return SearchSection(id: "recent", title: "Recently Played", results: recentResults)
    }
    
    private var searchSections: [SearchSection] {
        guard !searchResults.isEmpty else { return [] }
        
        let songs = searchResults.filter { $0.type == .song }
        let videos = searchResults.filter { $0.type == .video }
        
        var sections: [SearchSection] = []
        
        // Add songs section if we have songs
        if !songs.isEmpty {
            sections.append(SearchSection(id: "songs", title: "Songs", results: songs))
        }
        
        // Add videos section if we have videos
        if !videos.isEmpty {
            sections.append(SearchSection(id: "videos", title: "Videos", results: videos))
        }
        
        return sections
    }
    
    private var displaySections: [SearchSection] {
        // Handle empty state
        if state.searchText.isEmpty {
            return [recentlyPlayedSection]
        }
        
        // Handle search results
        if searchResults.isEmpty {
            return []
        }
        
        // Return all search sections
        return searchSections
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // DESIGN: Search field section
            SearchFieldView(
                searchText: $state.searchText,
                isFocused: $isFocused,
                isSearching: isSearching
            )
            .focused($isFocused) // DESIGN: Keyboard focus indicator
            .onChange(of: isFocused) { focused in
                print("🎯 [palette] Focus state changed: \(focused)")
            }
            .onAppear {
                DispatchQueue.main.async {
                    print("🎯 [palette] SearchField onAppear - setting focus to true")
                    isFocused = true
                }
            }
            .onChange(of: state.isVisible) { isVisible in
                if isVisible {
                    print("🎯 [palette] Palette became visible - aggressive focus")
                    // Aggressive focus when palette becomes visible
                    DispatchQueue.main.async {
                        print("🎯 [palette] Setting focus immediately")
                        isFocused = true
                    }
                    // Reinforce focus after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        print("🎯 [palette] Reinforcing focus at +10ms")
                        isFocused = true
                    }
                    // Extra reinforcement at longer delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        print("🎯 [palette] Extra focus enforcement at +50ms")
                        isFocused = true
                    }
                } else {
                    print("🎯 [palette] Palette hidden - clearing focus")
                    isFocused = false
                }
            }
            // Listen for explicit palette show signal from AppDelegate
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommandPaletteWillShow"))) { _ in
                DispatchQueue.main.async {
                    print("🎯 [palette] Received show signal, setting focus to search field")
                    isFocused = true
                }
            }
            
            // Main Content Area
            if isSearching {
                // Loading State
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if let error = searchError {
                // No Results State
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    Text("No results found")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Try updating your search terms to fetch results")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                    
                    Button(action: {
                        if let url = URL(string: error.searchUrl) {
                            NSWorkspace.shared.open(url)
                        }
                        CommandPalette.shared.toggle()
                    }) {
                        Text("Search on YouTube Music")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Results List
                SearchResultsList(
                    sections: displaySections,
                    selectedIndex: selectedIndex,
                    showRecent: state.searchText.isEmpty,
                    onSelect: handleSelection,
                    isKeyboardNavigation: isKeyboardNavigation,
                    isNavigatingUp: isNavigatingUp
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            // DESIGN: Bottom bar section
            HStack {
                // DESIGN: Left side - App branding
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                                            .resizable()
                                            // DESIGN: Icon size - adjust width and height
                                            .frame(width: 8, height: 12)
                                            .foregroundColor(.secondary)
                    Text("DropBeats v1.0")
                        // DESIGN: Font size for app branding text
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // DESIGN: Right side - Navigation hint text and icons
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        // DESIGN: Navigation icon size
                        .font(.caption2)
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text("to navigate")
                        // DESIGN: Navigation hint text size
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            // DESIGN: Bottom bar padding - adjust for spacing around content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    // DESIGN: Bottom bar background opacity - adjust for brightness
                    .fill(Color(.windowBackgroundColor).opacity(0.2))
                    .overlay(
                        Rectangle()
                            // DESIGN: Top border separator of bottom bar
                            .frame(height: 0.5)
                            .foregroundColor(Color.primary.opacity(0.05)),
                        alignment: .top
                    )
            )
        }
        // DESIGN: Window size (must match CommandPalette.swift setupWindow dimensions)
        .frame(width: 800, height: 400)
        .background(
            // DESIGN: Blur material - change to .hudWindow, .menu, .popover, etc for different effects
            VisualEffectView(material: .menu, blendingMode: .behindWindow)
        )
        .overlay(
            // DESIGN: Border styling - adjust cornerRadius, opacity, and lineWidth
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        // DESIGN: Corner radius - tweak this value for different roundedness
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .setupCommandPalette(
            isFocused: $isFocused,
            selectedIndex: $selectedIndex,
            displayResults: displaySections.flatMap { $0.results },
            searchText: state.searchText,
            onSearch: performSearch,
            onEscape: { CommandPalette.shared.toggle() },
            isKeyboardNavigation: $isKeyboardNavigation,
            isNavigatingUp: $isNavigatingUp
        )
        .onChange(of: state.searchText, perform: handleSearchTextChange)
        .onAppear {
            setupNotifications()
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PlaybackError"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let error = notification.userInfo?["error"] as? String,
               let url = notification.userInfo?["url"] as? String {
                self.playbackError = (error: error, url: url)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SearchResults"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let results = notification.userInfo?["results"] as? [SearchResult] {
                self.searchResults = results
                self.isSearching = false
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SearchError"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let error = notification.userInfo?["error"] as? String,
               let searchUrl = notification.userInfo?["searchUrl"] as? String {
                self.searchError = SearchError(
                    message: error == "NO_RESULTS" ? "No results found" : "Search failed",
                    searchUrl: searchUrl
                )
                self.isSearching = false
            }
        }
    }
    
    private func handleSearchTextChange(_ newValue: String) {
        guard !newValue.isEmpty else {
            searchResults = []
            isSearching = false
            searchError = nil
            return
        }
        searchError = nil
    }
    
    private func performSearch() {
        guard !state.searchText.isEmpty else { return }
        isSearching = true
        searchError = nil
        
        SearchService.shared.search(query: state.searchText) { results in
            print("���� [CommandPalette] Received search results:", results.count)
            self.searchResults = results
            print("📊 [CommandPalette] Results by type:", Dictionary(grouping: results, by: { $0.type.rawValue }).mapValues { $0.count })
            self.isSearching = false
        } onError: { error, searchUrl in
            searchError = SearchError(
                message: error == "NO_RESULTS" ? "No results found" : "Search failed",
                searchUrl: searchUrl
            )
            isSearching = false
        }
    }
    
    private func handleSelection(_ result: SearchResult) {
        // Convert SearchResult to Track
        let track = Track(
            id: result.id,
            title: result.title,
            artist: result.artist,
            albumArt: result.thumbnailUrl,
            duration: 0,  // Will be determined during playback
            isLiked: false,
            isPlaying: false,
            currentTime: 0
        )

        // Play track using playerManager
        Task {
            await playerManager.play(track: track)
        }

        CommandPalette.shared.toggle()
    }
}

// MARK: - View Modifiers
extension View {
    func setupCommandPalette(
        isFocused: FocusState<Bool>.Binding,
        selectedIndex: Binding<Int>,
        displayResults: [SearchResult],
        searchText: String,
        onSearch: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        isKeyboardNavigation: Binding<Bool>,
        isNavigatingUp: Binding<Bool>
    ) -> some View {
        self
            .onAppear {
                print("🎯 [palette] setupCommandPalette.onAppear called")
                selectedIndex.wrappedValue = 0
                print("🎯 [palette] Setting focus via modifier onAppear")
                isFocused.wrappedValue = true
                isKeyboardNavigation.wrappedValue = false
                isNavigatingUp.wrappedValue = false

                DispatchQueue.main.async {
                    print("🎯 [palette] Activating app from setupCommandPalette")
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.isVisible }) {
                        print("🎯 [palette] Making window key from setupCommandPalette")
                        window.makeKey()
                    }
                }
            }
            .onChange(of: CommandPaletteState.shared.isVisible) { isVisible in
                print("🎯 [palette] setupCommandPalette.onChange isVisible: \(isVisible)")
                if isVisible {
                    selectedIndex.wrappedValue = 0
                    print("🎯 [palette] Setting focus via modifier onChange")
                    isFocused.wrappedValue = true
                }
            }
            .onKeyPress(.upArrow) {
                isKeyboardNavigation.wrappedValue = true
                isNavigatingUp.wrappedValue = true
                selectedIndex.wrappedValue = (selectedIndex.wrappedValue - 1 + displayResults.count) % displayResults.count
                return .handled
            }
            .onKeyPress(.downArrow) {
                isKeyboardNavigation.wrappedValue = true
                isNavigatingUp.wrappedValue = false
                selectedIndex.wrappedValue = (selectedIndex.wrappedValue + 1) % displayResults.count
                return .handled
            }
            .onKeyPress(.return) {
                if !displayResults.isEmpty {
                    let selectedResult = displayResults[selectedIndex.wrappedValue]
                    // Convert SearchResult to Track and play via playerManager
                    let track = Track(
                        id: selectedResult.id,
                        title: selectedResult.title,
                        artist: selectedResult.artist,
                        albumArt: selectedResult.thumbnailUrl,
                        duration: 0,
                        isLiked: false,
                        isPlaying: false,
                        currentTime: 0
                    )
                    Task {
                        await MusicPlayerManager.shared.play(track: track)
                    }
                    CommandPalette.shared.toggle()
                } else if !searchText.isEmpty {
                    // Trigger search on Enter if there are no results yet
                    onSearch()
                }
                return .handled
            }
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
            .onChange(of: searchText) { _ in
                isKeyboardNavigation.wrappedValue = false
                isNavigatingUp.wrappedValue = false
            }
    }
} 
