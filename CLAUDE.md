# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DropBeats is a standalone macOS music player for YouTube Music consisting of:
- **macOS App** (Swift/SwiftUI) - Menu bar utility with direct audio streaming, album art display, and global keyboard shortcuts
- **Backend API** (Python/FastAPI) - HTTP API for search and stream URL extraction using ytmusicapi and yt-dlp
- **Infrastructure** (Supabase + Cloudflare Workers) - License management and webhooks

**Architecture:** The macOS app streams audio directly from YouTube Music using yt-dlp-extracted URLs, with search and recommendations powered by ytmusicapi via the Python backend. No browser or extension required.

## Build & Development Commands

### macOS Application

Build the app from root directory:
```bash
cd DropBeat
xcodebuild -project DropBeat.xcodeproj -scheme DropBeats -configuration Release clean build
```

Build and create DMG installer:
```bash
./scripts/build_dmg.sh
# Output: build/DropBeat.dmg
```

Package for Gumroad distribution (requires built app):
```bash
./scripts/package_app.sh <path/to/DropBeats.app>
# Output: dist/DropBeat.dmg and dist/DropBeat.zip
```

Open in Xcode:
```bash
open DropBeat/DropBeat.xcodeproj
```

### Python Backend API

Start the HTTP server:
```bash
cd Server/api
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Configuration (create `.env` from `.env.example`):
- `PORT`: HTTP API port (default: 8000)
- `YTMUSIC_OAUTH_FILE`: YouTube Music OAuth credentials
- `SEARCH_CACHE_DURATION`: Search cache TTL in seconds (default: 3600)
- `PLAYLIST_CACHE_DURATION`: Watch playlist cache TTL in seconds (default: 300)

**Dependencies:**
- `ytmusicapi` - YouTube Music API wrapper for search and recommendations
- `yt-dlp` - YouTube downloader for extracting direct stream URLs

### Cloudflare Workers

Deploy webhook proxy:
```bash
cd cloudflare/dropbeats-webhook-proxy
npm install
npm run deploy
```

Local development:
```bash
npm run dev
# Runs on port 8787
```

### Supabase

Start local Supabase stack:
```bash
cd Supabase
supabase start
# API: http://127.0.0.1:54321
# Studio: http://127.0.0.1:54323
# DB: postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

Stop local stack:
```bash
supabase stop
```

## Architecture

### Playback Flow

**How It Works:**
1. User searches for music via Command Palette (Cmd+Option+Space)
2. SearchService calls backend `/search/{query}` endpoint
3. Backend uses ytmusicapi to search YouTube Music and returns results
4. User selects a track → MusicPlayerManager.play(track)
5. YTDLPService fetches stream URL from backend `/stream-url/{videoId}`
6. Backend executes yt-dlp subprocess to extract direct audio stream URL (valid ~6 hours)
7. AudioPlayerService loads stream URL into AVPlayer and begins playback
8. When song ends or user clicks next, RecommendationService fetches auto-play tracks from `/watch-playlist/{videoId}`
9. Queue is auto-refilled when < 5 tracks remain
10. Next 2-3 tracks are pre-fetched in background for instant playback

**Benefits:**
- No browser dependency - works standalone
- No extension maintenance - no risk of YouTube UI changes breaking the app
- Direct audio streaming - better quality than browser audio capture
- Offline-capable backend - can self-host or use cloud deployment

### Key Components

**MusicPlayerManager.swift** ([DropBeat/DropBeat/Managers/MusicPlayerManager.swift](DropBeat/DropBeat/Managers/MusicPlayerManager.swift))
- Main playback orchestrator
- @Published state for UI reactivity: currentTrack, isPlaying, currentTime, duration, playbackQueue
- Integrates YTDLPService, AudioPlayerService, and RecommendationService
- Queue management with auto-refill when < 5 tracks
- Pre-fetching next 2-3 tracks for smooth playback
- Error handling with auto-skip for unavailable tracks

**AudioPlayerService.swift** ([DropBeat/DropBeat/Services/AudioPlayerService.swift](DropBeat/DropBeat/Services/AudioPlayerService.swift))
- AVPlayer wrapper with callback-based API
- 100ms time observer for smooth scrubber updates
- Playback end detection for auto-advance
- Buffering state monitoring
- Playback failure handling

**YTDLPService.swift** ([DropBeat/DropBeat/Services/YTDLPService.swift](DropBeat/DropBeat/Services/YTDLPService.swift))
- HTTP client for `/stream-url/{videoId}` backend endpoint
- 6-hour stream URL cache with automatic expiry cleanup
- Parallel pre-fetching for next 2-3 tracks
- Automatic URL refresh before playback if expired

**RecommendationService.swift** ([DropBeat/DropBeat/Services/RecommendationService.swift](DropBeat/DropBeat/Services/RecommendationService.swift))
- HTTP client for `/watch-playlist/{videoId}` endpoint (YouTube Music Radio)
- 5-minute recommendation cache per videoId
- Auto-triggers when queue < 5 tracks
- Returns ~25 tracks per request

**SearchService.swift** ([DropBeat/DropBeat/Services/SearchService.swift](DropBeat/DropBeat/Services/SearchService.swift))
- HTTP client for `/search/{query}` endpoint
- ytmusicapi-powered search across songs, albums, playlists, videos
- Country-specific search support
- Flattens categorized results into unified list

**License Service** ([DropBeat/DropBeat/Services/LicenseService.swift](DropBeat/DropBeat/Services/LicenseService.swift))
- Gumroad license key verification via Supabase
- 24-hour periodic validation
- Trial period management
- Cloudflare Workers proxy for webhook handling

**Command Palette** ([DropBeat/DropBeat/Features/CommandPalette/](DropBeat/DropBeat/Features/CommandPalette/))
- Global keyboard shortcut: Cmd+Option+Space
- Uses CFMachPort event tap for system-wide hotkey (works in fullscreen apps)
- Track search with SearchService
- Recent tracks display from MusicPlayerManager

### Backend API Endpoints

**GET /search/{query}?country={country}&limit={limit}**
- Search YouTube Music using ytmusicapi
- Returns songs, albums, playlists, videos, podcasts, episodes
- Response: `{"categories": {"songs": [...], "albums": [...]}, "total": 123}`

**GET /stream-url/{video_id}**
- Executes yt-dlp subprocess to extract direct stream URL
- Timeout: 10 seconds
- Returns: `{"videoId": "...", "streamUrl": "https://...", "expiresAt": "2025-12-27T..."}`
- Stream URL valid for ~6 hours

**GET /watch-playlist/{video_id}?limit={limit}**
- Fetch YouTube Music Radio recommendations using ytmusicapi.get_watch_playlist()
- Returns ~25 tracks similar to the input videoId
- Response: `{"tracks": [...], "total": 25}`

### Important Patterns

**Global Event Tap** ([AppDelegate.swift](DropBeat/DropBeat/AppDelegate.swift))
- Requires Accessibility permissions
- Uses `CGEvent.tapCreate` with `kCGHeadInsertEventTap` for global shortcuts
- Must be initialized in AppDelegate, not SwiftUI App lifecycle

**@MainActor for UI Safety**
- MusicPlayerManager marked with @MainActor to ensure all state updates happen on main thread
- Prevents UI update crashes and race conditions
- Task { @MainActor in ... } used in callbacks from background services

**Stream URL Caching Strategy**
- Stream URLs expire in ~6 hours (yt-dlp limitation)
- YTDLPService maintains cache with expiry timestamps
- Pre-fetching ensures next 2-3 tracks always have valid URLs
- Auto-refresh before playback if URL expired

**Error Handling Philosophy**
- Unavailable videos: Auto-skip with toast notification
- Network errors: Retry once, then skip
- Stream URL failures: Skip to next track
- Empty queue: Show "Search for a track" UI

**Album Art Theme Generation** ([AccessCard/](DropBeat/DropBeat/Features/AccessCard/))
- Extract dominant/accent colors from album artwork
- Generate dynamic gradients for menu bar UI
- Fallback to default theme if extraction fails

**Supabase Configuration**
- Public anon key stored in [SupabaseConfig.swift](DropBeat/DropBeat/Config/SupabaseConfig.swift)
- Used for license validation and user management
- Project URL: `https://trtxfdsssreqhuajpvqk.supabase.co`

## Code Organization

```
DropBeat/DropBeat/
├── Features/           # Feature-based modules (AccessCard, CommandPalette, etc.)
├── Managers/          # Core managers (MusicPlayerManager, AppState)
├── Services/          # External integrations (YTDLP, Recommendation, Search, License)
├── Models/            # Data models (Track, PlaybackState, License)
├── Config/            # Configuration (Supabase)
└── Utilities/         # Helper functions and extensions

Server/api/
└── main.py           # FastAPI app with HTTP endpoints (search, stream-url, watch-playlist)

Supabase/
├── functions/        # Edge functions (webhooks, license verification)
└── migrations/       # Database schema migrations

cloudflare/dropbeats-webhook-proxy/
└── src/worker.ts     # Gumroad webhook proxy
```

## Development Notes

### Backend API Response Formats

**Search Response:**
```json
{
  "categories": {
    "songs": [
      {
        "id": "videoId",
        "title": "Song Title",
        "artist": "Artist Name",
        "thumbnailUrl": "https://...",
        "duration": 180
      }
    ],
    "albums": [...],
    "playlists": [...],
    "videos": [...]
  },
  "total": 123
}
```

**Stream URL Response:**
```json
{
  "videoId": "abc123",
  "streamUrl": "https://rr5---sn-ab5szn7l.googlevideo.com/...",
  "expiresAt": "2025-12-27T12:00:00"
}
```

**Watch Playlist Response:**
```json
{
  "tracks": [
    {
      "id": "videoId",
      "title": "Song Title",
      "artist": "Artist Name",
      "albumArt": "https://...",
      "duration": 180,
      "isLiked": false,
      "isPlaying": false,
      "currentTime": 0
    }
  ],
  "total": 25
}
```

### License Verification Flow

1. User purchases via Gumroad → webhook to Cloudflare Worker
2. Cloudflare Worker validates and stores in Supabase
3. macOS app queries Supabase every 24 hours for validation
4. If validation fails, app enters trial/expired state

### macOS App Requirements

- **Minimum macOS:** 14.0 (Sonoma)
- **Entitlements:** Network client, Apple Events, file access (no server entitlement needed)
- **Permissions:** Accessibility (for global hotkey)
- **App Category:** Music
- **Background-only:** LSBackgroundOnly = true (no dock icon)

### Testing Backend Locally

1. Start Python backend: `cd Server/api && python -m uvicorn main:app --reload`
2. Test search endpoint: `curl http://localhost:8000/search/test`
3. Test stream URL endpoint: `curl http://localhost:8000/stream-url/abc123`
4. Test watch playlist endpoint: `curl http://localhost:8000/watch-playlist/abc123`
5. Run macOS app from Xcode
6. Search for music and verify playback works

### Common Issues

**Backend won't start:**
- Check yt-dlp is installed: `yt-dlp --version`
- Verify Python dependencies: `pip install -r requirements.txt`
- Check port 8000 is not in use: `lsof -i :8000`

**Stream URL fetch fails:**
- Verify yt-dlp is in PATH: `which yt-dlp`
- Check video is not region-locked or private
- Backend logs show yt-dlp subprocess output
- Stream URLs expire in ~6 hours

**Search returns no results:**
- Check ytmusicapi authentication (oauth.json or headers_auth.json)
- Verify backend can reach YouTube Music API
- Check backend logs for ytmusicapi errors

**Global hotkey not working:**
- Verify Accessibility permissions granted in System Preferences
- Check for conflicting keyboard shortcuts
- Ensure AppDelegate event tap is initialized

**License validation failing:**
- Verify Supabase credentials in SupabaseConfig.swift
- Check network connectivity to Supabase
- Review Cloudflare Worker logs for webhook delivery

**Audio playback stutters:**
- Check network connection quality
- Verify stream URL is not expired (should auto-refresh)
- macOS may throttle network when on battery - plug in to test

## Distribution

- **macOS App:** Distributed via Gumroad as DMG or ZIP
- **Backend:** Self-hosted or cloud deployment (Render, Railway, Fly.io)
  - Render.com deployment requires: Python 3.11+, yt-dlp system package
  - Environment variables: YTMUSIC_OAUTH_FILE, PORT, SEARCH_CACHE_DURATION

## Current Phase

Phase 4: yt-dlp Migration
- Main branch: `main`
- Current branch: `yt-dlp`
- Focus: Migrate from Chrome Extension + WebSocket to standalone yt-dlp architecture
- Status: Implementation complete, ready for testing
