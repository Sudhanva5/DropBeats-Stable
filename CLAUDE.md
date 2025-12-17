# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DropBeats is a multi-platform music control application for YouTube Music consisting of:
- **macOS App** (Swift/SwiftUI) - Menu bar utility with album art display and global keyboard shortcuts
- **Chrome Extension** (JavaScript) - Browser integration for YouTube Music
- **Backend API** (Python/FastAPI) - WebSocket server for real-time sync between clients
- **Infrastructure** (Supabase + Cloudflare Workers) - License management and webhooks

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

Start the WebSocket server:
```bash
cd Server/api
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
# WebSocket runs on port 8089
```

Configuration (create `.env` from `.env.example`):
- `PORT`: HTTP API port (default: 8000)
- `WS_PORT`: WebSocket port (default: 8089)
- `YTMUSIC_OAUTH_FILE`: YouTube Music OAuth credentials
- `SEARCH_CACHE_DURATION`: Search cache TTL in seconds (default: 3600)

### Chrome Extension

No build step required - load unpacked extension in Chrome:
1. Navigate to `chrome://extensions`
2. Enable Developer Mode
3. Click "Load unpacked" and select `ChromeExtension/` directory

To update after code changes, click the refresh button in `chrome://extensions`.

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

### WebSocket Communication

All clients communicate via a centralized FastAPI WebSocket server on port 8089. The protocol uses JSON messages with specific types:

**Message Types:**
- `track_update` - Current track metadata
- `ping` / `pong` - Heartbeat (5s interval, 15s timeout)
- `search_request` / `search_response` - Track search
- `recent_tracks` - Recently played tracks

**Connection Flow:**
1. Chrome extension scrapes YouTube Music DOM → sends `track_update` to server
2. Server broadcasts to all connected clients (macOS app, other extensions)
3. macOS app receives and updates UI
4. Ping/pong heartbeat ensures connection health

**Important:** ANY incoming WebSocket message resets the connection timeout timer, not just PING/PONG. This prevents false "dead connection" detection during active data flow.

### Key Components

**WebSocketManager.swift** ([DropBeat/DropBeat/Managers/WebSocketManager.swift](DropBeat/DropBeat/Managers/WebSocketManager.swift))
- NWListener-based WebSocket server (port 8089)
- Ping/pong heartbeat with exponential backoff reconnection
- Track state management and recent tracks caching
- Connection health monitoring with automatic recovery

**License Service** ([DropBeat/DropBeat/Services/LicenseService.swift](DropBeat/DropBeat/Services/LicenseService.swift))
- Gumroad license key verification via Supabase
- 24-hour periodic validation
- Trial period management
- Cloudflare Workers proxy for webhook handling

**Command Palette** ([DropBeat/DropBeat/Features/CommandPalette/](DropBeat/DropBeat/Features/CommandPalette/))
- Global keyboard shortcut: Cmd+Option+Space
- Uses CFMachPort event tap for system-wide hotkey (works in fullscreen apps)
- Track search with server-side caching
- Recent tracks display

**Chrome Extension** ([ChromeExtension/](ChromeExtension/))
- `content.js`: DOM scraping of YouTube Music player state
- `background.js`: WebSocket client and state management
- Manifest v3 service worker architecture

### Important Patterns

**Global Event Tap** ([AppDelegate.swift](DropBeat/DropBeat/AppDelegate.swift))
- Requires Accessibility permissions
- Uses `CGEvent.tapCreate` with `kCGHeadInsertEventTap` for global shortcuts
- Must be initialized in AppDelegate, not SwiftUI App lifecycle

**Connection Resilience**
- Exponential backoff: 1s initial → 60s max delay
- Port checking every 30s when disconnected
- Multiple connection attempts before declaring failure
- Both client and server implement heartbeat independently

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
├── Managers/          # Core managers (WebSocket, AppState)
├── Services/          # External integrations (License, Gumroad)
├── Models/            # Data models (Track, License)
├── Config/            # Configuration (Supabase)
└── Utilities/         # Helper functions and extensions

ChromeExtension/
├── background.js      # Service worker, WebSocket client
├── content.js         # YouTube Music DOM integration
├── popup.js/html      # Extension popup UI
└── manifest.json      # Extension configuration

Server/api/
└── main.py           # FastAPI app with WebSocket endpoints

Supabase/
├── functions/        # Edge functions (webhooks, license verification)
└── migrations/       # Database schema migrations

cloudflare/dropbeats-webhook-proxy/
└── src/worker.ts     # Gumroad webhook proxy
```

## Development Notes

### WebSocket Message Format

Track update message structure:
```json
{
  "type": "track_update",
  "title": "Song Title",
  "artist": "Artist Name",
  "album": "Album Name",
  "albumArtUrl": "https://...",
  "duration": "3:45",
  "timestamp": 1234567890
}
```

### License Verification Flow

1. User purchases via Gumroad → webhook to Cloudflare Worker
2. Cloudflare Worker validates and stores in Supabase
3. macOS app queries Supabase every 24 hours for validation
4. If validation fails, app enters trial/expired state

### macOS App Requirements

- **Minimum macOS:** 14.0 (Sonoma)
- **Entitlements:** Network client/server, Apple Events, file access
- **Permissions:** Accessibility (for global hotkey)
- **App Category:** Music
- **Background-only:** LSBackgroundOnly = true (no dock icon)

### Testing WebSocket Locally

1. Start Python backend: `cd Server/api && python -m uvicorn main:app --reload`
2. Open YouTube Music in Chrome with extension loaded
3. Run macOS app from Xcode
4. Verify connection logs in both extension console and Xcode console

### Common Issues

**WebSocket won't connect:**
- Check port 8089 is not blocked by firewall
- Verify Python server is running: `lsof -i :8089`
- Check Chrome extension has host permissions for `music.youtube.com`

**Global hotkey not working:**
- Verify Accessibility permissions granted in System Preferences
- Check for conflicting keyboard shortcuts
- Ensure AppDelegate event tap is initialized

**License validation failing:**
- Verify Supabase credentials in SupabaseConfig.swift
- Check network connectivity to Supabase
- Review Cloudflare Worker logs for webhook delivery

## Distribution

- **macOS App:** Distributed via Gumroad as DMG or ZIP
- **Chrome Extension:** Chrome Web Store (planned)
- **Backend:** Self-hosted or cloud deployment (Render, Railway, etc.)

## Current Phase

Phase 4: Beta Launch
- Main branch: `main`
- Current branch: `phase4-beta-launch`
- Focus: Stability, UX polish, distribution readiness
