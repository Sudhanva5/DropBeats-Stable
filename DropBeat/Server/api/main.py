from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from ytmusicapi import YTMusic
from typing import Dict, List, Optional, Set
import json
import asyncio
import logging
import time
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="DropBeat Music API")

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize YTMusic
try:
    # Try to initialize with OAuth
    ytmusic = YTMusic('oauth.json')
except Exception as e:
    logger.warning(f"OAuth initialization failed: {e}, falling back to browser authentication")
    try:
        # Fall back to browser authentication
        ytmusic = YTMusic('headers_auth.json')
    except Exception as e:
        logger.warning(f"Browser authentication failed: {e}, falling back to unauthenticated mode")
        ytmusic = YTMusic()

# WebSocket connections
active_connections: Set[WebSocket] = set()

# Simple cache
cache: Dict[str, tuple[List, float]] = {}
CACHE_DURATION = 3600  # 1 hour

# Cache for playlist details to avoid repeated fetches
playlist_cache: Dict[str, tuple[dict, float]] = {}
PLAYLIST_CACHE_DURATION = 300  # 5 minutes

@app.get("/health")
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
async def test_search(query: str, limit: int = 5):
    """Test endpoint for search functionality"""
    try:
        results = await search(query, limit)
        return results
    except Exception as e:
        logger.error(f"Search test failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    client_id = id(websocket)
    await websocket.accept()
    active_connections.add(websocket)
    logger.info(f"🔌 New WebSocket connection established (ID: {client_id})")
    
    try:
        while True:
            try:
                message = await websocket.receive_text()
                data = json.loads(message)
                logger.info(f"📥 [{client_id}] Received message: {data}")
                
                if data["type"] == "PING":
                    logger.info(f"🏓 [{client_id}] Received PING, sending PONG")
                    await websocket.send_json({
                        "type": "PONG",
                        "timestamp": time.time()
                    })
                
                elif data["type"] == "SEARCH":
                    try:
                        query = data["query"]
                        logger.info(f"🔍 [{client_id}] Processing search request for: {query}")
                        results = await search(query)
                        logger.info(f"✅ [{client_id}] Search completed, found {results['total']} results")
                        logger.debug(f"📦 [{client_id}] Raw search results: {results}")
                        
                        # Send back all songs
                        response = {
                            "type": "SEARCH_RESULTS",
                            "data": results  # Send the complete results object
                        }
                        logger.info(f"📤 [{client_id}] Sending search results back: {response}")
                        await websocket.send_json(response)
                        logger.info(f"✅ [{client_id}] Search results sent successfully")
                        
                    except Exception as e:
                        logger.error(f"❌ [{client_id}] Search error: {str(e)}", exc_info=True)
                        await websocket.send_json({
                            "type": "ERROR",
                            "error": str(e)
                        })
                
                elif data["type"] == "COMMAND":
                    # Forward command to all other connections (Chrome extension)
                    logger.info(f"📤 [{client_id}] Forwarding command to other connections: {data}")
                    for conn in active_connections:
                        if conn != websocket:
                            await conn.send_text(message)
                
                elif data["type"] == "TRACK_INFO":
                    # Forward track info to all other connections (Swift app)
                    logger.info(f"📤 [{client_id}] Forwarding track info to other connections: {data}")
                    for conn in active_connections:
                        if conn != websocket:
                            await conn.send_text(message)
            except json.JSONDecodeError as e:
                logger.error(f"❌ [{client_id}] Invalid JSON received: {str(e)}")
                continue
            except Exception as e:
                logger.error(f"❌ [{client_id}] Error processing message: {str(e)}", exc_info=True)
                continue
    
    except Exception as e:
        logger.error(f"❌ [{client_id}] WebSocket error: {str(e)}", exc_info=True)
    finally:
        active_connections.remove(websocket)
        logger.info(f"🔌 [{client_id}] WebSocket connection closed")
        try:
            await websocket.close()
        except:
            pass

async def search(query: str, limit: Optional[int] = 20):
    try:
        logger.info(f"🔍 Starting search for: {query}")
        
        # Check cache
        cache_key = f"{query}_{limit}"
        if cache_key in cache:
            results, timestamp = cache[cache_key]
            if time.time() - timestamp < CACHE_DURATION:
                logger.info(f"💾 Cache hit for query: {query}")
                return results

        # Track seen IDs to avoid duplicates
        seen_ids = set()
        song_results = []
        
        # Search for songs
        logger.info("🎵 Performing YTMusic search...")
        search_results = ytmusic.search(query, limit=50)  # Increased limit to get more results
        logger.info(f"✅ Found {len(search_results)} results")
        logger.debug(f"Raw search results: {search_results}")
        
        for item in search_results:
            try:
                # Get and validate ID
                video_id = item.get("videoId")
                
                # Skip if no video ID (we only want songs)
                if not video_id:
                    logger.debug(f"⚠️ Skipping item without video ID: {item}")
                    continue
                
                # Skip if we've seen this ID before
                if video_id in seen_ids:
                    logger.debug(f"⚠️ Skipping duplicate ID: {video_id}")
                    continue
                
                seen_ids.add(video_id)
                
                # Skip channel results
                if item.get("resultType") == "channel":
                    logger.debug(f"⚠️ Skipping channel result: {video_id}")
                    continue
                    
                # Get artists
                artists = []
                if item.get("artists"):
                    for artist in item["artists"]:
                        if isinstance(artist, dict) and artist.get("name"):
                            artists.append(artist["name"])
                
                # Get thumbnail
                thumbnail = None
                if item.get("thumbnails"):
                    thumbnails = item["thumbnails"]
                    if thumbnails:
                        thumbnail = thumbnails[-1]["url"]
                
                # Skip if title is missing or empty
                title = item.get("title", "").strip()
                if not title:
                    logger.debug(f"⚠️ Skipping item without title: {video_id}")
                    continue
                
                # Create result object
                result = {
                    "id": video_id,
                    "title": title,
                    "artist": " & ".join(artists) if artists else item.get("author", "Unknown Artist"),
                    "thumbnailUrl": thumbnail,
                    "type": "song",
                    "duration": item.get("duration", "")
                }
                
                # Add to results if it's a song (based on category or type)
                category = item.get("category", "").lower()
                item_type = str(item.get("type", "")).lower()
                
                # Debug log to see what we're getting
                logger.debug(f"Item category: {category}, type: {item_type}, title: {title}")
                
                # More inclusive filtering - if it has a video ID, it's likely playable
                if video_id:  # If it has a video ID, we can play it
                    song_results.append(result)
                    logger.debug(f"📝 Added song: {result['title']} (category: {category}, type: {item_type})")
                else:
                    logger.debug(f"⚠️ Skipping: {title} - no video ID (category: {category}, type: {item_type})")
                
                # Limit to top 20 songs
                if len(song_results) >= 20:
                    break
                
            except Exception as e:
                logger.error(f"❌ Error formatting result: {str(e)}", exc_info=True)
                continue

        logger.info(f"Found {len(song_results)} songs")

        # Prepare response
        response = {
            "categories": {"songs": song_results},  # Keep structure for backward compatibility
            "cached": False,
            "total": len(song_results)
        }

        # Cache results
        cache[cache_key] = (response, time.time())
        logger.info(f"✅ Search completed successfully with {response['total']} songs")
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

@app.on_event("startup")
async def startup_event():
    logger.info("Starting DropBeat Music API")
    try:
        ytmusic.search("test", limit=1)
        logger.info("YTMusic connection successful")
    except Exception as e:
        logger.error(f"YTMusic connection failed: {e}")
        raise

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000) 