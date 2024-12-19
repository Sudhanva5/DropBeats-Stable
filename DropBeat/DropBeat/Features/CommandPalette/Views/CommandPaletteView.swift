import SwiftUI

struct CommandPaletteView: View {
    @State private var state = CommandPaletteState.shared
    @FocusState private var isFocused: Bool
    @State private var selectedIndex = 0
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var searchError: SearchError?
    @State private var playbackError: (error: String, url: String)?
    
    @ObservedObject private var wsManager = WebSocketManager.shared
    
    private var recentlyPlayedSection: SearchSection {
        let recentResults = wsManager.recentTracks.compactMap { track -> SearchResult? in
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
        let playlists = searchResults.filter { $0.type == .playlist }
        
        return [
            SearchSection(id: "songs", title: "Songs", results: songs.prefix(5).map { $0 }),
            SearchSection(id: "playlists", title: "Playlists", results: playlists.prefix(5).map { $0 })
        ].filter { !$0.results.isEmpty }
    }
    
    private var displaySections: [SearchSection] {
        state.searchText.isEmpty ? [recentlyPlayedSection] : searchSections
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(
                searchText: $state.searchText,
                isFocused: $isFocused,
                isSearching: isSearching
            )
            
            if !wsManager.isConnected {
                Text("Connecting to YouTube Music...")
                    .foregroundColor(.secondary)
                    .padding()
            } else if let error = playbackError {
                VStack(spacing: 12) {
                    Text("Couldn't play the song directly")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if let url = URL(string: error.url) {
                            NSWorkspace.shared.open(url)
                        }
                        CommandPalette.shared.toggle()
                    }) {
                        Text("Open in YouTube Music")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            } else if let error = searchError {
                VStack(spacing: 12) {
                    Text("Couldn't find any results")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if let url = URL(string: error.searchUrl) {
                            NSWorkspace.shared.open(url)
                        }
                        CommandPalette.shared.toggle()
                    }) {
                        Text("Search in YouTube Music")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            } else {
                SearchResultsList(
                    sections: displaySections,
                    selectedIndex: selectedIndex,
                    showRecent: state.searchText.isEmpty,
                    onSelect: handleSelection
                )
            }
        }
        .frame(width: 800, height: 400)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .setupCommandPalette(
            isFocused: $isFocused,
            selectedIndex: $selectedIndex,
            displayResults: displaySections.flatMap { $0.results },
            searchText: state.searchText,
            onSearch: performSearch,
            onEscape: { CommandPalette.shared.toggle() }
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
        guard wsManager.isConnected else {
            print("⚠️ Cannot search: WebSocket not connected")
            return
        }
        
        isSearching = true
        searchError = nil
        
        wsManager.search(query: state.searchText) { results in
            print("🔍 [CommandPalette] Received search results:", results.count)
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
        wsManager.play(id: result.id, type: result.type)
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
        onEscape: @escaping () -> Void
    ) -> some View {
        self
            .onAppear {
                selectedIndex.wrappedValue = 0
                isFocused.wrappedValue = true
                
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.isVisible }) {
                        window.makeKey()
                    }
                }
            }
            .onChange(of: CommandPaletteState.shared.isVisible) { isVisible in
                if isVisible {
                    selectedIndex.wrappedValue = 0
                    isFocused.wrappedValue = true
                }
            }
            .onKeyPress(.upArrow) {
                selectedIndex.wrappedValue = (selectedIndex.wrappedValue - 1 + displayResults.count) % displayResults.count
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectedIndex.wrappedValue = (selectedIndex.wrappedValue + 1) % displayResults.count
                return .handled
            }
            .onKeyPress(.return) {
                if !displayResults.isEmpty {
                    let selectedResult = displayResults[selectedIndex.wrappedValue]
                    WebSocketManager.shared.play(id: selectedResult.id, type: selectedResult.type)
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
    }
} 
