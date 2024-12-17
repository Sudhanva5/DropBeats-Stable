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
ytmusic = YTMusic()

# WebSocket connections
active_connections: Set[WebSocket] = set()

# Simple cache
cache: Dict[str, tuple[List, float]] = {}
CACHE_DURATION = 3600  # 1 hour

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
                        
                        # Send back the entire results object
                        response = {
                            "type": "SEARCH_RESULTS",
                            "results": results["categories"]["songs"]  # Only sending songs for now
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

        # Initialize categories
        categorized_results = {
            "songs": [],
            "playlists": [],
            "albums": [],
            "videos": [],
            "podcasts": [],
            "episodes": []
        }
        
        # Track seen IDs to avoid duplicates
        seen_ids = set()
        
        # Search for songs
        logger.info("🎵 Performing YTMusic search...")
        search_results = ytmusic.search(query, limit=limit)
        logger.info(f"✅ Found {len(search_results)} results")
        logger.debug(f"Raw search results: {search_results}")
        
        for item in search_results:
            try:
                # Get and validate ID
                video_id = item.get("videoId")
                browse_id = item.get("browseId")
                
                # Skip if no valid ID
                if not video_id and not browse_id:
                    logger.debug(f"⚠️ Skipping item without valid ID: {item}")
                    continue
                
                # Use appropriate ID
                item_id = video_id if video_id else browse_id
                
                # Skip if we've seen this ID before
                if item_id in seen_ids:
                    logger.debug(f"⚠️ Skipping duplicate ID: {item_id}")
                    continue
                
                seen_ids.add(item_id)
                
                # Skip channel results (these often have Unknown Title/Artist)
                if item.get("resultType") == "channel" or (browse_id and browse_id.startswith("UC")):
                    logger.debug(f"⚠️ Skipping channel result: {item_id}")
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
                
                # Determine result type based on YTMusic's category
                category = item.get("category", "").lower()
                result_type = "song"  # default type
                
                # Debug logging
                logger.debug(f"Processing item - Category: {category}, Type: {item.get('type', 'unknown')}")
                
                # Map YTMusic categories to our types
                if "song" in category or "song" in str(item.get("type", "")).lower():
                    result_type = "song"
                elif "album" in category or "album" in str(item.get("type", "")).lower():
                    result_type = "album"
                elif "playlist" in category or "playlist" in str(item.get("type", "")).lower():
                    result_type = "playlist"
                elif "podcast" in category or "podcast" in str(item.get("type", "")).lower():
                    result_type = "podcast"
                elif "episode" in category or "episode" in str(item.get("type", "")).lower():
                    result_type = "episode"
                elif "video" in category or "video" in str(item.get("type", "")).lower():
                    result_type = "video"
                
                logger.debug(f"Mapped type: {result_type}")
                
                # Skip if title is missing or empty
                title = item.get("title", "").strip()
                if not title:
                    logger.debug(f"⚠️ Skipping item without title: {item_id}")
                    continue
                
                # Create result object
                result = {
                    "id": item_id,
                    "title": title,
                    "artist": " & ".join(artists) if artists else item.get("author", "Unknown Artist"),
                    "thumbnailUrl": thumbnail,
                    "type": result_type,
                    "duration": item.get("duration", ""),
                    "album": item.get("album", {}).get("name") if item.get("album") else None
                }
                
                # Add to appropriate category
                category = result_type + "s"  # pluralize for category name
                if category in categorized_results and len(categorized_results[category]) < 5:
                    categorized_results[category].append(result)
                    logger.debug(f"📝 Added to {category}: {result['title']}")
                
            except Exception as e:
                logger.error(f"❌ Error formatting result: {str(e)}", exc_info=True)
                continue

        # Log category counts for debugging
        for category, results in categorized_results.items():
            logger.info(f"Category {category}: {len(results)} results")

        # Prepare response
        response = {
            "categories": categorized_results,
            "cached": False,
            "total": sum(len(results) for results in categorized_results.values())
        }

        # Cache results
        cache[cache_key] = (response, time.time())
        logger.info(f"✅ Search completed successfully with {response['total']} total results")
        return response
    
    except Exception as e:
        logger.error(f"❌ Search error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")

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