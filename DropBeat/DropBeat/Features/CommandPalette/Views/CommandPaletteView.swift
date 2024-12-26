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
        
        return [
            SearchSection(id: "songs", title: "Songs", results: songs.prefix(10).map { $0 })
        ]
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
        
        // Group and filter results
        let songs = searchResults.filter { $0.type == .song }
        if songs.isEmpty {
            return []
        }
        
        return [
            SearchSection(id: "songs", title: "Songs", results: songs.prefix(10).map { $0 })
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            SearchFieldView(
                searchText: $state.searchText,
                isFocused: $isFocused,
                isSearching: isSearching
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onChange(of: state.isVisible) { isVisible in
                if isVisible {
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
            }
            
            // Main Content Area
            if !wsManager.isConnected {
                // Connection Lost State
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    Text("Connection to server lost")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Please check if the app is running")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if isSearching {
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
            
            // Bottom Bar
            HStack {
                // Left side - App branding
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                                            .resizable()
                                            .frame(width: 8, height: 12)
                                            .foregroundColor(.secondary)
                    Text("DropBeats v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Right side - Navigation hint
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text("to navigate")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color(.windowBackgroundColor).opacity(0.5))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(Color.primary.opacity(0.1)),
                        alignment: .top
                    )
            )
        }
        .frame(width: 800, height: 400)
        .background(
            ZStack {
                // Blur layer
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                // Overlay color
                Color(.windowBackgroundColor)
                    .opacity(0.85)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
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
        guard wsManager.isConnected else {
            print("⚠️ Cannot search: WebSocket not connected")
            return
        }
        
        isSearching = true
        searchError = nil
        
        wsManager.search(query: state.searchText) { results in
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
        onEscape: @escaping () -> Void,
        isKeyboardNavigation: Binding<Bool>,
        isNavigatingUp: Binding<Bool>
    ) -> some View {
        self
            .onAppear {
                selectedIndex.wrappedValue = 0
                isFocused.wrappedValue = true
                isKeyboardNavigation.wrappedValue = false
                isNavigatingUp.wrappedValue = false
                
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
            .onChange(of: searchText) { _ in
                isKeyboardNavigation.wrappedValue = false
                isNavigatingUp.wrappedValue = false
            }
    }
} 
