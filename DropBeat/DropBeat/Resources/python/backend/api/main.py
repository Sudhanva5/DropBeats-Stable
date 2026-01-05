from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from ytmusicapi import YTMusic
from typing import Dict, List, Optional, Set
import json
import asyncio
import logging
import time
import uvicorn
import os
from dotenv import load_dotenv
from enum import Enum
from dataclasses import dataclass
from datetime import datetime

# Load environment variables
load_dotenv()

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Cache configuration
cache: Dict[str, tuple[List, float]] = {}
CACHE_DURATION = int(os.getenv("SEARCH_CACHE_DURATION", 3600))  # 1 hour default

# Add after cache configuration
playlist_cache: Dict[str, tuple[dict, float]] = {}
PLAYLIST_CACHE_DURATION = int(os.getenv("PLAYLIST_CACHE_DURATION", 300))  # 5 minutes default

class ClientType(Enum):
    MACOS_APP = "macos_app"
    CHROME_EXTENSION = "chrome_extension"

@dataclass
class Client:
    websocket: WebSocket
    client_type: ClientType
    last_pong: float
    connected_at: datetime

app = FastAPI(title="DropBeat Music API")

# Enable CORS with environment configuration
allowed_origins = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize YTMusic with environment configuration
ytmusic_oauth = os.getenv("YTMUSIC_OAUTH_FILE", "oauth.json")
ytmusic_headers = os.getenv("YTMUSIC_HEADERS_FILE", "headers_auth.json")

try:
    ytmusic = YTMusic(ytmusic_oauth)
except Exception as e:
    logger.warning(f"OAuth initialization failed: {e}, falling back to browser authentication")
    try:
        ytmusic = YTMusic(ytmusic_headers)
    except Exception as e:
        logger.warning(f"Browser authentication failed: {e}, falling back to unauthenticated mode")
        ytmusic = YTMusic()

# WebSocket connections
active_connections: Set[WebSocket] = set()

class ConnectionManager:
    def __init__(self):
        self.active_clients: Dict[int, Client] = {}
        self.ping_interval = 5  # seconds
        self.pong_timeout = 15  # seconds
        
    async def connect(self, websocket: WebSocket, client_type: ClientType):
        await websocket.accept()
        client_id = id(websocket)
        self.active_clients[client_id] = Client(
            websocket=websocket,
            client_type=client_type,
            last_pong=time.time(),
            connected_at=datetime.now()
        )
        logger.info(f"🔌 New {client_type.value} connection established (ID: {client_id})")
        
    def disconnect(self, websocket: WebSocket):
        client_id = id(websocket)
        if client_id in self.active_clients:
            client = self.active_clients[client_id]
            logger.info(f"🔌 {client.client_type.value} disconnected (ID: {client_id})")
            del self.active_clients[client_id]
            
    async def broadcast(self, message: dict, exclude: Optional[WebSocket] = None):
        for client_id, client in list(self.active_clients.items()):
            if client.websocket != exclude:
                try:
                    await client.websocket.send_json(message)
                except Exception as e:
                    logger.error(f"❌ Error broadcasting to client {client_id}: {e}")
                    await self.handle_disconnection(client.websocket)
                    
    async def send_to_type(self, message: dict, client_type: ClientType):
        for client_id, client in list(self.active_clients.items()):
            if client.client_type == client_type:
                try:
                    await client.websocket.send_json(message)
                except Exception as e:
                    logger.error(f"❌ Error sending to {client_type.value} {client_id}: {e}")
                    await self.handle_disconnection(client.websocket)
    
    async def handle_disconnection(self, websocket: WebSocket):
        try:
            await websocket.close()
        except:
            pass
        self.disconnect(websocket)
    
    async def start_ping_loop(self):
        while True:
            await asyncio.sleep(self.ping_interval)
            await self.check_connections()
    
    async def check_connections(self):
        current_time = time.time()
        for client_id, client in list(self.active_clients.items()):
            if current_time - client.last_pong > self.pong_timeout:
                logger.warning(f"⚠️ Client {client_id} ({client.client_type.value}) timed out")
                await self.handle_disconnection(client.websocket)
            else:
                try:
                    await client.websocket.send_json({"type": "PING", "timestamp": current_time})
                except Exception as e:
                    logger.error(f"❌ Error sending ping to {client_id}: {e}")
                    await self.handle_disconnection(client.websocket)

    def update_pong(self, websocket: WebSocket):
        client_id = id(websocket)
        if client_id in self.active_clients:
            self.active_clients[client_id].last_pong = time.time()

manager = ConnectionManager()

@app.get("/health")
@app.head("/health")
async def health_check():
    """Check if the server is running"""
    return {"status": "healthy", "timestamp": time.time()}

@app.get("/test-ytmusic")
async def test_ytmusic():
    """Test if YTMusic API is working"""
    try:
        # Try a simple search
        test_query = "test"
        results = ytmusic.search(test_query, limit=1)
        return {
            "status": "ok",
            "message": "YTMusic API is working",
            "sample_results": results
        }
    except Exception as e:
        logger.error(f"YTMusic test failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/search/{query}")
async def test_search(query: str, country: Optional[str] = None, limit: Optional[int] = None):
    """Test endpoint for search functionality"""
    try:
        results = await search(query, country=country, limit=limit)
        return results
    except Exception as e:
        logger.error(f"Search test failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    client_type = None
    try:
        # Wait for initial message to determine client type
        initial_message = await websocket.receive_text()
        data = json.loads(initial_message)
        
        if data.get("type") != "IDENTIFY":
            raise ValueError("First message must be IDENTIFY")
            
        client_type_str = data.get("client")
        try:
            client_type = ClientType(client_type_str)
        except ValueError:
            raise ValueError(f"Invalid client type: {client_type_str}")
        
        await manager.connect(websocket, client_type)
        
        while True:
            try:
                message = await websocket.receive_text()
                data = json.loads(message)
                logger.info(f"📥 [{id(websocket)}] Received message: {data}")
                
                if data["type"] == "PING":
                    logger.info(f"🏓 [{id(websocket)}] Received PING, sending PONG")
                    await websocket.send_json({
                        "type": "PONG",
                        "timestamp": time.time()
                    })
                    manager.update_pong(websocket)
                
                elif data["type"] == "PONG":
                    manager.update_pong(websocket)
                
                elif data["type"] == "SEARCH":
                    try:
                        query = data["query"]
                        country = data.get("country", "Unknown")
                        logger.info(f"🔍 [{id(websocket)}] Processing search request: {query} (Country: {country})")
                        results = await search(query, country=country)
                        await websocket.send_json({
                            "type": "SEARCH_RESULTS",
                            "data": results
                        })
                    except Exception as e:
                        logger.error(f"❌ Search error: {str(e)}")
                        await websocket.send_json({
                            "type": "ERROR",
                            "error": str(e)
                        })
                
                elif data["type"] == "COMMAND":
                    # Forward commands from macOS app to Chrome extension
                    if client_type == ClientType.MACOS_APP:
                        await manager.send_to_type(data, ClientType.CHROME_EXTENSION)
                
                elif data["type"] == "TRACK_INFO":
                    # Forward track info from Chrome extension to macOS app
                    if client_type == ClientType.CHROME_EXTENSION:
                        await manager.send_to_type(data, ClientType.MACOS_APP)
                
            except json.JSONDecodeError as e:
                logger.error(f"❌ [{id(websocket)}] Invalid JSON received: {str(e)}")
                continue
            except Exception as e:
                logger.error(f"❌ [{id(websocket)}] Error processing message: {str(e)}", exc_info=True)
                continue
    
    except WebSocketDisconnect:
        logger.info(f"🔌 WebSocket disconnected normally")
    except Exception as e:
        logger.error(f"❌ WebSocket error: {str(e)}", exc_info=True)
    finally:
        await manager.handle_disconnection(websocket)

async def search(query: str, country: str = "India", limit: Optional[int] = 25):
    try:
        logger.info(f"🔍 Starting search for: {query} (Country: {country})")
        
        # Check cache with country
        cache_key = f"{query}_{country}_{limit}"
        if cache_key in cache:
            results, timestamp = cache[cache_key]
            if time.time() - timestamp < CACHE_DURATION:
                logger.info(f"💾 Cache hit for query: {query}")
                return results

        # Track seen IDs to avoid duplicates
        seen_ids = set()
        song_results = []
        video_results = []
        
        # Search for songs
        logger.info("🎵 Performing YTMusic song search...")
        song_search_results = ytmusic.search(
            query=query,
            filter="songs",
            limit=50,  # Increased to get more candidates for better filtering
            ignore_spelling=False
        )
        
        # Search for videos
        logger.info("🎥 Performing YTMusic video search...")
        video_search_results = ytmusic.search(
            query=query,
            filter="videos",
            limit=25,  # Fewer videos since they're lower priority
            ignore_spelling=False
        )
        
        logger.info(f"✅ Found {len(song_search_results)} songs and {len(video_search_results)} videos")
        
        # Helper function to score results
        def score_result(item, is_video=False):
            score = 0
            title = item.get("title", "").lower()
            query_lower = query.lower()
            
            # Artist name matching (high priority)
            artists = []
            if item.get("artists"):
                for artist in item["artists"]:
                    if isinstance(artist, dict) and artist.get("name"):
                        artist_name = artist["name"].lower()
                        artists.append(artist_name)
                        if query_lower == artist_name:
                            score += 400  # Highest priority for exact artist match
                        elif query_lower in artist_name:
                            score += 300  # High priority for partial artist match
            
            # Title matching
            if query_lower == title:
                score += 300
            elif query_lower in title:
                score += 150
            
            # Videos start with a penalty
            if is_video:
                score -= 100
            
            # Album matching (high visibility)
            album_name = item.get("album", {}).get("name", "").lower()
            if album_name:
                if query_lower == album_name:
                    score += 250  # Strong boost for exact album match
                elif query_lower in album_name:
                    score += 150  # Good boost for partial album match
            
            # Regional content boost (reduced for international artists)
            if country != "Unknown":
                is_international_artist = any(query_lower in artist.lower() for artist in artists)
                
                if not is_international_artist:
                    # Apply regional boosts only for non-international artists
                    artist_country = item.get("artist", {}).get("country", "").lower()
                    if artist_country and artist_country.lower() == country.lower():
                        score += 100  # Reduced from 150
                    
                    content_language = item.get("language", "").lower()
                    if content_language:
                        country_language_map = {
                            "india": ["hindi", "tamil", "telugu", "kannada", "malayalam"],
                            "japan": ["japanese"],
                            "korea": ["korean"],
                        }
                        
                        if country.lower() in country_language_map:
                            if content_language in country_language_map[country.lower()]:
                                score += 75  # Reduced from 100
            
            # Official artist/channel verification (increased importance)
            if "topic" in (item.get("author", "").lower()):
                score += 300  # Increased from 250
            
            # Verified artists (increased importance)
            if item.get("isVerified", False):
                score += 150  # Increased from 100
            
            # Duration penalty for very short or long content
            duration = item.get("duration", "")
            if duration:
                duration_parts = duration.split(":")
                if len(duration_parts) >= 2:
                    minutes = int(duration_parts[-2])
                    if minutes < 2 or minutes > 8:
                        score -= 50
            
            # Popularity bonus (increased weight)
            if item.get("views"):
                try:
                    views = int(item["views"].replace(",", ""))
                    view_score = min(300, int(75 * (1 + views / 10000000)))  # Increased from 200/50
                    score += view_score
                except (ValueError, AttributeError):
                    pass
            
            # Recent content bonus
            if item.get("year"):
                try:
                    year = int(item["year"])
                    current_year = datetime.now().year
                    if year == current_year:
                        score += 50
                    elif year == current_year - 1:
                        score += 30
                except (ValueError, TypeError):
                    pass
            
            return score
        
        # Process songs and videos
        scored_results = []
        
        # Process songs
        for item in song_search_results:
            try:
                video_id = item.get("videoId")
                if not video_id or video_id in seen_ids:
                    continue
                
                seen_ids.add(video_id)
                
                # Get artists with better handling
                artists = []
                if item.get("artists"):
                    for artist in item["artists"]:
                        if isinstance(artist, dict) and artist.get("name"):
                            artists.append(artist["name"])
                
                # Get high-quality thumbnail
                thumbnail = None
                if item.get("thumbnails"):
                    thumbnails = item["thumbnails"]
                    if thumbnails:
                        thumbnail = thumbnails[-1]["url"]
                
                result = {
                    "id": video_id,
                    "title": item.get("title").strip(),
                    "artist": " & ".join(artists) if artists else item.get("author", "Unknown Artist"),
                    "thumbnailUrl": thumbnail,
                    "type": "song",
                    "duration": item.get("duration", "")
                }
                
                score = score_result(item)
                scored_results.append((score, result))
                
            except Exception as e:
                logger.error(f"❌ Error formatting song result: {str(e)}", exc_info=True)
                continue
        
        # Process videos
        for item in video_search_results:
            try:
                video_id = item.get("videoId")
                if not video_id or video_id in seen_ids:
                    continue
                
                seen_ids.add(video_id)
                
                result = {
                    "id": video_id,
                    "title": item.get("title").strip(),
                    "artist": item.get("author", "Unknown Artist"),
                    "thumbnailUrl": item.get("thumbnails", [{}])[-1].get("url"),
                    "type": "video",
                    "duration": item.get("duration", "")
                }
                
                score = score_result(item, is_video=True)
                scored_results.append((score, result))
                
            except Exception as e:
                logger.error(f"❌ Error formatting video result: {str(e)}", exc_info=True)
                continue

        # Sort by score and take top results
        scored_results.sort(key=lambda x: x[0], reverse=True)
        final_limit = limit if limit is not None else 25
        final_results = [result for score, result in scored_results[:final_limit]]
        
        logger.info(f"Found {len(final_results)} high-quality results")

        # Prepare response
        response = {
            "categories": {"songs": final_results},
            "cached": False,
            "total": len(final_results)
        }

        # Cache results
        cache[cache_key] = (response, time.time())
        logger.info(f"✅ Search completed successfully with {response['total']} results")
        return response
    
    except Exception as e:
        logger.error(f"❌ Search error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")

@app.get("/playlist/{playlist_id}")
async def get_playlist(playlist_id: str):
    """Get playlist details and tracks"""
    try:
        # Remove VL prefix if present
        if playlist_id.startswith("VL"):
            playlist_id = playlist_id[2:]
        
        # Check cache
        if playlist_id in playlist_cache:
            playlist_data, timestamp = playlist_cache[playlist_id]
            if time.time() - timestamp < PLAYLIST_CACHE_DURATION:
                logger.info(f"💾 Cache hit for playlist: {playlist_id}")
                return playlist_data
        
        logger.info(f"🎵 Fetching playlist: {playlist_id}")
        playlist_data = ytmusic.get_playlist(playlist_id, limit=None)
        
        # Cache the result
        playlist_cache[playlist_id] = (playlist_data, time.time())
        
        return playlist_data
    except Exception as e:
        logger.error(f"Failed to get playlist {playlist_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/playlist/{playlist_id}/refresh")
async def refresh_playlist(playlist_id: str):
    """Force refresh a playlist's cache"""
    try:
        # Remove VL prefix if present
        if playlist_id.startswith("VL"):
            playlist_id = playlist_id[2:]
        
        # Remove from cache to force refresh
        if playlist_id in playlist_cache:
            del playlist_cache[playlist_id]
        
        # Fetch fresh data
        playlist_data = ytmusic.get_playlist(playlist_id, limit=None)
        
        # Update cache
        playlist_cache[playlist_id] = (playlist_data, time.time())
        
        return {"status": "success", "message": "Playlist refreshed"}
    except Exception as e:
        logger.error(f"Failed to refresh playlist {playlist_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/playlist/{playlist_id}/first-song")
async def get_first_playable_song(playlist_id: str):
    """Get the first playable song from a playlist"""
    try:
        # Remove VL prefix if present
        if playlist_id.startswith("VL"):
            playlist_id = playlist_id[2:]
        
        logger.info(f"🎵 Getting first playable song for playlist: {playlist_id}")
        
        # Get playlist data
        playlist_data = ytmusic.get_playlist(playlist_id, limit=None)
        
        # Find first playable song
        for track in playlist_data.get('tracks', []):
            video_id = track.get('videoId')
            if video_id and not track.get('isAvailable', True):
                continue
            
            if video_id:
                logger.info(f"✅ Found first playable song: {video_id}")
                return {
                    "videoId": video_id,
                    "title": track.get('title', ''),
                    "artist": track.get('artists', [{}])[0].get('name', 'Unknown Artist')
                }
        
        raise HTTPException(status_code=404, detail="No playable songs found in playlist")
        
    except Exception as e:
        logger.error(f"Failed to get first playable song from playlist {playlist_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/watch-playlist/{video_id}")
async def get_watch_playlist(video_id: str, limit: int = 25):
    """Get YouTube Music Radio recommendations for auto-play"""
    try:
        logger.info(f"🎵 Fetching watch playlist for video: {video_id}")

        # Get watch playlist from ytmusicapi (YouTube Music Radio)
        watch_playlist = ytmusic.get_watch_playlist(videoId=video_id, limit=limit)

        # Parse tracks into simplified format
        tracks = []
        for item in watch_playlist.get('tracks', []):
            video_id_item = item.get('videoId')
            if not video_id_item:
                continue

            # Get artists
            artists = []
            if item.get('artists'):
                for artist in item['artists']:
                    if isinstance(artist, dict) and artist.get('name'):
                        artists.append(artist['name'])

            # Get thumbnail
            thumbnail = None
            if item.get('thumbnails'):
                thumbnails = item['thumbnails']
                if thumbnails:
                    thumbnail = thumbnails[-1]['url']

            # Parse duration to seconds
            duration_str = item.get('duration', '0:00')
            try:
                parts = duration_str.split(':')
                if len(parts) == 2:
                    duration = int(parts[0]) * 60 + int(parts[1])
                elif len(parts) == 3:
                    duration = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                else:
                    duration = 0
            except (ValueError, IndexError):
                duration = 0

            tracks.append({
                'id': video_id_item,
                'title': item.get('title', '').strip(),
                'artist': ' & '.join(artists) if artists else 'Unknown Artist',
                'albumArt': thumbnail,
                'duration': duration,
                'isLiked': False,
                'isPlaying': False,
                'currentTime': 0
            })

        logger.info(f"✅ Found {len(tracks)} recommendations")
        return {'tracks': tracks, 'total': len(tracks)}

    except Exception as e:
        logger.error(f"❌ Failed to get watch playlist for {video_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Watch playlist failed: {str(e)}")

@app.get("/stream-url/{video_id}")
async def get_stream_url(video_id: str):
    """Get yt-dlp stream URL for direct playback (valid ~6 hours)"""
    try:
        import subprocess
        logger.info(f"🎵 Fetching stream URL for video: {video_id}")

        # Execute yt-dlp to get direct stream URL
        youtube_url = f"https://music.youtube.com/watch?v={video_id}"

        # Request M4A/MP4 audio format (AAC codec) for AVPlayer compatibility
        result = subprocess.run(
            ['yt-dlp', '-f', 'bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio', '-g', youtube_url],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            error_msg = result.stderr.strip() if result.stderr else "Unknown error"
            logger.error(f"❌ yt-dlp failed for {video_id}: {error_msg}")
            raise HTTPException(status_code=500, detail=f"yt-dlp failed: {error_msg}")

        stream_url = result.stdout.strip()

        if not stream_url:
            raise HTTPException(status_code=500, detail="yt-dlp returned empty stream URL")

        # Stream URLs expire in approximately 6 hours
        from datetime import timedelta
        expires_at = datetime.now() + timedelta(hours=6)

        logger.info(f"✅ Got stream URL for {video_id}")
        return {
            'videoId': video_id,
            'streamUrl': stream_url,
            'expiresAt': expires_at.isoformat()
        }

    except subprocess.TimeoutExpired:
        logger.error(f"❌ yt-dlp timeout for {video_id}")
        raise HTTPException(status_code=504, detail="yt-dlp request timed out after 10 seconds")
    except Exception as e:
        logger.error(f"❌ Failed to get stream URL for {video_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Stream URL fetch failed: {str(e)}")

@app.get("/song-info/{video_id}")
async def get_song_info(video_id: str):
    """Get song metadata (title, author, duration, thumbnail) using yt-dlp"""
    try:
        import subprocess
        logger.info(f"🎵 Fetching song info for video: {video_id}")

        youtube_url = f"https://music.youtube.com/watch?v={video_id}"

        # Use yt-dlp to get video metadata (JSON output)
        result = subprocess.run(
            ['yt-dlp', '--dump-json', youtube_url],
            capture_output=True,
            text=True,
            timeout=15
        )

        if result.returncode != 0:
            error_msg = result.stderr.strip() if result.stderr else "Unknown error"
            logger.error(f"❌ yt-dlp failed for {video_id}: {error_msg}")
            raise HTTPException(status_code=500, detail=f"yt-dlp failed: {error_msg}")

        if not result.stdout:
            raise HTTPException(status_code=500, detail="yt-dlp returned empty metadata")

        # Parse JSON output
        metadata = json.loads(result.stdout)

        # Extract required fields
        title = metadata.get('title', 'Unknown Title')
        author = metadata.get('uploader', metadata.get('channel', 'Unknown Artist'))
        duration = metadata.get('duration', 0)

        # Get best thumbnail
        thumbnails = metadata.get('thumbnails', [])
        thumbnail = thumbnails[-1]['url'] if thumbnails else None

        logger.info(f"✅ Got song info for {video_id}: {title} by {author}")
        return {
            'videoId': video_id,
            'title': title,
            'author': author,
            'duration': duration,
            'thumbnail': thumbnail
        }

    except subprocess.TimeoutExpired:
        logger.error(f"❌ yt-dlp timeout for {video_id}")
        raise HTTPException(status_code=504, detail="yt-dlp request timed out after 15 seconds")
    except json.JSONDecodeError as e:
        logger.error(f"❌ Failed to parse yt-dlp JSON for {video_id}: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to parse video metadata")
    except Exception as e:
        logger.error(f"❌ Failed to get song info for {video_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Song info fetch failed: {str(e)}")

@app.on_event("startup")
async def startup_event():
    environment = os.getenv("ENVIRONMENT", "development")
    port = int(os.getenv("PORT", 8000))
    ws_port = int(os.getenv("WS_PORT", 8089))
    
    logger.info(f"Starting DropBeat Music API in {environment} mode")
    logger.info(f"HTTP server running on port {port}")
    logger.info(f"WebSocket server running on port {ws_port}")
    
    # Test YTMusic connection (non-blocking)
    try:
        ytmusic.search("test", limit=1)
        logger.info("✅ YTMusic connection successful")
    except Exception as e:
        logger.warning(f"⚠️ YTMusic connection failed: {e}")
        logger.warning("   Search functionality may be limited, but server will continue")
    
    # Start the ping loop
    asyncio.create_task(manager.start_ping_loop())

if __name__ == "__main__":
    port = int(os.getenv("PORT", 4002))
    uvicorn.run(app, host="0.0.0.0", port=port) 
