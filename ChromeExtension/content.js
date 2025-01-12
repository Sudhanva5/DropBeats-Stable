// Force console display for all log levels
console.defaultLevel = 'trace';

// Immediate logging with distinctive styling
console.log('%c[DropBeat] 🚀 CONTENT SCRIPT STARTING', 'background: #ff0000; color: white; font-size: 20px; padding: 10px;');
console.log('%c[DropBeat] 📍 URL:', 'background: #000; color: #fff; padding: 5px;', window.location.href);

// Add a global error handler to catch any script errors
window.onerror = function(msg, url, line, col, error) {
    console.error('%c[DropBeat] ❌ Global Error:', 'background: #ff0000; color: white;', {
        message: msg,
        url: url,
        line: line,
        col: col,
        error: error
    });
    return false;
};

// Add unhandled promise rejection handler
window.onunhandledrejection = function(event) {
    console.error('%c[DropBeat] ❌ Unhandled Promise Rejection:', 'background: #ff0000; color: white;', {
        reason: event.reason
    });
};

console.log('🎵 [DropBeat] Content script loaded for YouTube Music');

let lastTrackInfo = null;
let currentTrackId = null;
let lastTrackSignature = null;

// Add state tracking
let youtubeMusiceReady = false;
let navigationInProgress = false;

// State management object
window._dropbeatState = window._dropbeatState || {
    lastTrackInfo: null,
    isConnected: false,
    observers: {},
    initialized: false,
    videoEvents: null
};

// Navigation state tracking
const navigationState = {
    isNavigating: false,
    lastNavigationTime: Date.now(),
    pendingHealthCheck: false,
    navigationCount: 0,
    lastUrl: window.location.href
};

// Add at the top after initial declarations
let lastActivityTime = Date.now();
let lastHealthCheckTime = Date.now();
let initializeAttempts = 0;
let healthCheckInterval;

// Setup navigation observer
function setupNavigationObserver() {
    console.log('🔍 [DropBeat] Setting up navigation observer');
    
    // Create an observer instance
    const observer = new MutationObserver(async (mutations) => {
        for (const mutation of mutations) {
            if (mutation.type === 'childList' || mutation.type === 'attributes') {
                const currentUrl = window.location.href;
                if (currentUrl !== navigationState.lastUrl) {
                    navigationState.lastUrl = currentUrl;
                    navigationState.navigationCount++;
                    navigationState.lastNavigationTime = Date.now();
                    console.log('🔄 [DropBeat] Navigation detected:', currentUrl);
                    await handleUrlChange();
                }
            }
        }
    });

    // Start observing
    observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src', 'href']
    });

    window._dropbeatState.observers.navigation = observer;
    console.log('✅ [DropBeat] Navigation observer setup complete');
}

// Enhanced activity tracking
function updateActivityTimestamp(type = 'user') {
    lastActivityTime = Date.now();
    lastHealthCheckTime = Date.now(); // Reset health check timer on activity
    console.log('🕒 [DropBeat] Activity timestamp updated:', type);
}

// Enhanced health check system
async function performHealthCheck(force = false) {
    const now = Date.now();
    const timeSinceLastCheck = now - lastHealthCheckTime;
    
    // Skip if we checked recently (within 30 seconds) unless forced
    if (!force && timeSinceLastCheck < 30000) {
        return true;
    }
    
    try {
        // Basic element checks
        const video = document.querySelector('video');
        const playerBar = document.querySelector('ytmusic-player-bar');
        const player = getYTMusicPlayer();
        
        // Check if player is responsive
        const isPlayerResponsive = player && typeof player.getPlayerState === 'function';
        
        // Check if we can get current track info
        const trackInfo = getTrackInfo();
        const hasTrackInfo = !!trackInfo;
        
        // Check WebSocket connection
        let isWebSocketHealthy = false;
        try {
            const response = await chrome.runtime.sendMessage({ type: 'GET_CONNECTION_STATUS' });
            isWebSocketHealthy = response?.isConnected === true;
        } catch (error) {
            console.log('⚠️ [DropBeat] WebSocket health check failed:', error);
        }
        
        const isHealthy = !!(
            video && 
            playerBar && 
            isPlayerResponsive && 
            hasTrackInfo && 
            isWebSocketHealthy
        );
        
        console.log('🏥 [DropBeat] Health check:', {
            source: force ? 'forced' : 'automatic',
            hasVideo: !!video,
            hasPlayerBar: !!playerBar,
            isPlayerResponsive,
            hasTrackInfo,
            isWebSocketHealthy,
            overall: isHealthy,
            timeSinceLastCheck: Math.round(timeSinceLastCheck / 1000) + 's'
        });
        
        lastHealthCheckTime = now;
        
        if (!isHealthy) {
            console.log('⚠️ [DropBeat] Health check failed, reinitializing...');
            await initialize(true);
            return false;
        }
        
        // Update activity timestamp on successful health check
        updateActivityTimestamp('health_check');
        return isHealthy;
    } catch (error) {
        console.error('❌ [DropBeat] Health check error:', error);
        return false;
    }
}

// Setup periodic health checks with progressive intervals
function setupHealthChecks() {
    if (healthCheckInterval) {
        clearInterval(healthCheckInterval);
    }
    
    healthCheckInterval = setInterval(async () => {
        const inactiveTime = Date.now() - lastActivityTime;
        
        // Progressive check frequency based on inactivity duration
        if (inactiveTime > 5 * 60 * 1000) { // After 5 minutes
            console.log('⚠️ [DropBeat] Long inactivity detected, performing thorough check');
            await performHealthCheck(true);
        } else if (inactiveTime > 2 * 60 * 1000) { // After 2 minutes
            console.log('⚠️ [DropBeat] Medium inactivity detected, performing health check');
            await performHealthCheck(false);
        }
    }, 30 * 1000); // Check every 30 seconds
}

// Enhanced initialize function
async function initialize(forceReinit = false) {
    console.log('%c[DropBeat] 🎯 INITIALIZE CALLED', 'background: #00ff00; color: black; font-size: 15px; padding: 5px;', {
        forceReinit,
        hasExistingState: window._dropbeatState.initialized,
        navigationCount: navigationState.navigationCount
    });
    
    setupHealthChecks();  // Setup health checks on initialization
    
    // Rest of the existing initialize function...
    // ... existing code ...
}

// Track more types of activity
document.addEventListener('mousemove', () => updateActivityTimestamp('mouse'));
document.addEventListener('keydown', () => updateActivityTimestamp('keyboard'));
document.addEventListener('click', () => updateActivityTimestamp('click'));

// Track player activity
function setupPlayerActivityTracking() {
    const video = document.querySelector('video');
    if (video) {
        ['play', 'pause', 'timeupdate', 'seeking', 'seeked'].forEach(event => {
            video.addEventListener(event, () => updateActivityTimestamp('player'));
        });
    }
}

// Track network activity
const originalFetch = window.fetch;
window.fetch = function(...args) {
    updateActivityTimestamp('network');
    return originalFetch.apply(this, args);
};

// Add periodic check for inactivity
setInterval(() => {
    const inactiveTime = Date.now() - lastActivityTime;
    if (inactiveTime > 5 * 60 * 1000) { // 5 minutes
        console.log('⚠️ [DropBeat] Detected inactivity:', Math.round(inactiveTime/1000), 'seconds');
        // Force reinitialize
        initializeAttempts = 0;
        initialize(true);
        // Reset activity timer
        updateActivityTimestamp();
    }
}, 30 * 1000); // Check every 30 seconds

// Network request monitoring using XMLHttpRequest
const originalXHR = window.XMLHttpRequest.prototype.open;
window.XMLHttpRequest.prototype.open = function(method, url) {
    console.log('🔄 [DropBeat Debug] XHR intercepted:', url);
    
    if (typeof url === 'string') {
        try {
            // Track initialization state
            const urlObj = new URL(url, window.location.origin);
            const listId = urlObj.searchParams.get('list');
            
            // Log all relevant requests for playlist initialization
            if (url.includes('browse') && listId) {
                console.log('📋 [DropBeat Debug] Playlist metadata request:', url);
            }
            if (url.includes('/next')) {
                console.log('🎵 [DropBeat Debug] Queue initialization request:', url);
            }
            if (url.includes('/player')) {
                console.log('▶️ [DropBeat Debug] Player initialization request:', url);
            }
            
            // Enhanced playlist handling after player initialization
            if (url.includes('/player') && window.location.href.includes('list=')) {
                this.addEventListener('load', function() {
                    try {
                        console.log('✅ [DropBeat Debug] Player initialization complete');
                        // Wait for everything to be ready
                        setTimeout(async () => {
                            const success = await handlePlaylistPlayback();
                            if (!success) {
                                console.log('⚠️ [DropBeat Debug] First attempt failed, retrying with delay');
                                setTimeout(() => handlePlaylistPlayback(), 2000);
                            }
                        }, 1000);
                    } catch (error) {
                        console.error('❌ [DropBeat Debug] Error handling player init:', error);
                    }
                });
            }
        } catch (error) {
            console.warn('⚠️ [DropBeat Debug] Error in XHR handling:', error);
        }
    }
    
    return originalXHR.apply(this, arguments);
};

// Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📥 [DropBeat] Content received message:', message, 'from sender:', sender);

    try {
        if (message.type === 'COMMAND_PALETTE_OPENED') {
            console.log('🎯 [DropBeat] Command palette opened, starting progressive health check');
            
            // Initial immediate check
            performHealthCheck(true).then(async isHealthy => {
                if (isHealthy) {
                    console.log('✅ [DropBeat] Initial health check passed');
                    updateActivityTimestamp('command_palette');
                    
                    // One verification check after a delay
                    setTimeout(async () => {
                        const verificationHealth = await performHealthCheck(true);
                        if (!verificationHealth) {
                            console.log('⚠️ [DropBeat] Verification check failed, reinitializing...');
                            await initialize(true);
                        } else {
                            console.log('✅ [DropBeat] Verification check passed');
                            updateTrackInfo(true);
                        }
                    }, 400);
                } else {
                    console.log('⚠️ [DropBeat] Initial health check failed, starting progressive checks');
                    
                    // Progressive checks if unhealthy
                    let success = false;
                    for (let i = 0; i < 2 && !success; i++) {
                        await new Promise(resolve => setTimeout(resolve, 300 * (i + 1)));
                        success = await performHealthCheck(true);
                        if (success) {
                            console.log('✅ [DropBeat] Progressive check passed on attempt', i + 1);
                            await initialize(true);
                            updateTrackInfo(true);
                            break;
                        }
                    }
                    
                    if (!success) {
                        console.log('❌ [DropBeat] All health checks failed, forcing reinitialization');
                        await initialize(true);
                    }
                }
                sendResponse({ success: true });
            });
            return true; // Keep the message channel open for async response
        } else if (message.type === 'HEALTH_CHECK') {
            // Return health status based on critical elements
            const video = document.querySelector('video');
            const playerBar = document.querySelector('ytmusic-player-bar');
            const player = getYTMusicPlayer();
            
            const isHealthy = !!(video && playerBar && player);
            console.log('🏥 [DropBeat] Health check:', isHealthy ? 'healthy' : 'unhealthy');
            
            sendResponse({ 
                healthy: isHealthy,
                timestamp: message.timestamp,
                elements: {
                    hasVideo: !!video,
                    hasPlayerBar: !!playerBar,
                    hasPlayer: !!player
                }
            });
        } else if (message.type === 'RECONNECT') {
            console.log('🔄 [DropBeat] Reconnection request received');
            // Reset state
            youtubeMusiceReady = false;
            navigationInProgress = false;
            
            // Re-initialize everything
            initialize();
            
            // If we have a URL, check if it's a playlist
            if (message.url?.includes('list=')) {
                console.log('📋 [DropBeat] Playlist URL detected after reconnect');
                setTimeout(async () => {
                    const success = await handlePlaylistPlayback();
                    if (!success) {
                        console.log('⚠️ [DropBeat] First attempt failed, retrying with delay');
                        setTimeout(() => handlePlaylistPlayback(), 2000);
                    }
                }, 1000);
            }
            
            sendResponse({ success: true });
        } else if (message.type === 'CONNECTION_STATUS') {
            const oldState = window._dropbeatState.isConnected;
            window._dropbeatState.isConnected = message.status.isConnected;
            console.log('🔌 [DropBeat] Connection status updated:', window._dropbeatState.isConnected);
            
            // If we just got connected, send initial track info
            if (!oldState && window._dropbeatState.isConnected) {
                console.log('🎵 [DropBeat] Initially connected, sending track info');
                updateTrackInfo(true); // force update
            }
            sendResponse({ received: true });
        } else if (message.type === 'COMMAND') {
            console.log('🎮 [DropBeat] Handling command:', message.command, 'with data:', message.data);
            handleCommand(message.command, message);
            sendResponse({ received: true });
        } else if (message.type === 'PING') {
            console.log('🏓 [DropBeat] Ping received, sending pong');
            sendResponse({ pong: true });
        }
    } catch (error) {
        console.error('❌ [DropBeat] Error handling message:', error);
        sendResponse({ error: error.message });
    }
    
    return true; // Keep the message channel open for async response
});

// Define multiple selectors for each control, ordered by reliability
const selectors = {
    playPause: [
        'button[aria-label*="Play"], button[aria-label*="Pause"]',
        '.play-pause-button',
        'button[role="button"][title*="Play"], button[role="button"][title*="Pause"]',
        '[data-testid="play-pause-button"]',
        '.ytmusic-player-bar button[aria-label*="Play"], .ytmusic-player-bar button[aria-label*="Pause"]',
        'tp-yt-paper-icon-button.play-pause-button'
    ],
    next: [
        'button[aria-label*="Next"]',
        '.next-button',
        'button[role="button"][title*="Next"]',
        '[data-testid="next-button"]',
        '.ytmusic-player-bar button[aria-label*="Next"]',
        'tp-yt-paper-icon-button.next-button'
    ],
    previous: [
        'button[aria-label*="Previous"]',
        '.previous-button',
        'button[role="button"][title*="Previous"]',
        '[data-testid="previous-button"]',
        '.ytmusic-player-bar button[aria-label*="Previous"]',
        'tp-yt-paper-icon-button.previous-button'
    ],
    like: [
        'ytmusic-like-button-renderer',
        'button[aria-label*="like"]',
        '[data-testid="like-button-renderer"]'
    ]
};

// Helper function to find elements with multiple selector attempts
function findElement(selectorList) {
    if (Array.isArray(selectorList)) {
        for (const selector of selectorList) {
            const element = document.querySelector(selector);
            if (element) {
                console.log('✅ [DropBeat] Found element with selector:', selector);
                return element;
            }
        }
        console.warn('⚠️ [DropBeat] No element found for selectors:', selectorList);
    } else {
        const element = document.querySelector(selectorList);
        if (element) {
            console.log('✅ [DropBeat] Found element with selector:', selectorList);
            return element;
        }
        console.warn('⚠️ [DropBeat] No element found for selector:', selectorList);
    }
    return null;
}

function handleCommand(command, message) {
    console.log('🎮 [DropBeat] Handling command:', command, 'with full message:', message);
    
    // Helper function to wait for track change
    const waitForTrackChange = (currentSignature, timeout = 3000) => {
        return new Promise((resolve) => {
            const startTime = Date.now();
            const checkInterval = setInterval(() => {
                const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                const title = titleElement?.textContent?.trim() || '';
                const artist = artistElement?.textContent?.trim() || '';
                const newSignature = `${title}-${artist}`;

                if (newSignature !== currentSignature && title !== '') {
                    clearInterval(checkInterval);
                    // Add a small delay to let YouTube Music stabilize
                    setTimeout(() => resolve(true), 150);
                } else if (Date.now() - startTime > timeout) {
                    clearInterval(checkInterval);
                    resolve(false);
                }
            }, 100);
        });
    };

    // Helper function to verify track hasn't changed
    const verifyTrackUnchanged = (originalSignature) => {
        const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
        const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
        const currentSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
        return currentSignature === originalSignature;
    };

    // Helper function to wait for play state change with track verification
    const waitForPlayStateChange = (wasPlaying, originalSignature, timeout = 2000) => {
        return new Promise((resolve) => {
            const startTime = Date.now();
            let stabilityCounter = 0;
            let lastPlayState = null;
            const checkInterval = setInterval(() => {
                const video = document.querySelector('video');
                const isNowPlaying = !video?.paused;
                
                // Check if play state has changed from last check
                if (lastPlayState !== isNowPlaying) {
                    stabilityCounter = 0;
                    lastPlayState = isNowPlaying;
                } else {
                    stabilityCounter++;
                }
                
                // If we have a stable state for 3 consecutive checks
                if (stabilityCounter >= 3) {
                    clearInterval(checkInterval);
                    
                    // Verify track state one final time
                    if (!verifyTrackUnchanged(originalSignature)) {
                        resolve({ changed: false, reason: 'track_changed' });
                    } else {
                        resolve({ changed: true, isPlaying: isNowPlaying });
                    }
                    return;
                }

                if (Date.now() - startTime > timeout) {
                    clearInterval(checkInterval);
                    resolve({ changed: false, reason: 'timeout' });
                }
            }, 50); // Check more frequently
        });
    };
    
    try {
        switch (command) {
            case 'play': {
                // Handle playing specific songs by ID
                if (message?.data?.id) {
                    console.log('🎵 [DropBeat] Playing specific song - ID:', message.data.id);
                    const songUrl = `https://music.youtube.com/watch?v=${message.data.id}`;
                    window.location.href = songUrl;
                    return;
                }
                // Fall through to togglePlayPause if no ID provided
            }
            case 'pause':
            case 'togglePlayPause': {
                const button = findElement(selectors.playPause);
                if (button) {
                    console.log('⏯️ [DropBeat] Found play/pause button, clicking...');
                    const video = document.querySelector('video');
                    const wasPlaying = !video?.paused;
                    
                    // Get current track signature before clicking
                    const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                    const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                    const originalSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
                    
                    // Click the button
                    button.click();
                    
                    // Wait for state to stabilize and verify
                    waitForPlayStateChange(wasPlaying, originalSignature).then(result => {
                        if (result.changed) {
                            if (verifyTrackUnchanged(originalSignature)) {
                                updateTrackInfo(true);
                            } else {
                                console.warn('⚠️ [DropBeat] Track changed during play/pause operation');
                                updateTrackInfo(true);
                            }
                        } else {
                            console.warn('⚠️ [DropBeat] Play state did not change as expected');
                            updateTrackInfo(true);
                        }
                    });
                }
                break;
            }
            case 'next':
            case 'previous': {
                const button = findElement(selectors[command]);
                if (button) {
                    console.log(`⏭️ [DropBeat] Found ${command} button, clicking...`);
                    
                    const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                    const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                    const currentSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
                    
                    // Add a small delay before clicking
                    setTimeout(() => {
                        // Click the button
                        button.click();
                        
                        // Wait for track change with increased timeout
                        waitForTrackChange(currentSignature, 3000).then(changed => {
                            // Add a delay before updating to let YouTube Music stabilize
                            setTimeout(() => {
                                if (changed) {
                                    updateTrackInfo(true);
                                } else {
                                    console.warn(`⚠️ [DropBeat] Track did not change after ${command} command`);
                                    updateTrackInfo(true);
                                }
                            }, 150);
                        });
                    }, 100);
                }
                break;
            }
            case 'seek': {
                const video = document.querySelector('video');
                if (video && message?.data?.position !== undefined) {
                    const position = Number(message.data.position);
                    if (isNaN(position)) {
                        console.warn('⚠️ [DropBeat] Invalid seek position:', message.data.position);
                        return;
                    }
                    
                    console.log('⏩ [DropBeat] Seeking to position:', position);
                    
                    try {
                        // Get track signature before seeking
                        const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                        const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                        const originalSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
                        
                        // Store current track info and state
                        const wasPlaying = !video.paused;
                        
                        // Set the video position
                        video.currentTime = position;
                        
                        // Wait a short time to verify seek was successful
                        setTimeout(() => {
                            // Verify track hasn't changed
                            if (!verifyTrackUnchanged(originalSignature)) {
                                console.warn('⚠️ [DropBeat] Track changed during seek operation');
                                updateTrackInfo(true);
                                return;
                            }
                            
                            // Verify seek position
                            const actualPosition = video.currentTime;
                            if (Math.abs(actualPosition - position) > 1) {
                                console.warn('⚠️ [DropBeat] Seek position verification failed');
                                // Update with actual position
                                const updatedTrackInfo = {
                                    ...lastTrackInfo,
                                    currentTime: actualPosition
                                };
                                lastTrackInfo = updatedTrackInfo;
                                chrome.runtime.sendMessage({
                                    type: 'TRACK_INFO',
                                    data: updatedTrackInfo
                                });
                                return;
                            }
                            
                            // Restore play state if needed
                            if (wasPlaying && video.paused) {
                                video.play();
                            }
                            
                            // Update track info with verified position
                            const updatedTrackInfo = {
                                ...lastTrackInfo,
                                currentTime: actualPosition,
                                isPlaying: !video.paused
                            };
                            lastTrackInfo = updatedTrackInfo;
                            chrome.runtime.sendMessage({
                                type: 'TRACK_INFO',
                                data: updatedTrackInfo
                            });
                        }, 100);
                    } catch (error) {
                        console.error('❌ [DropBeat] Error seeking:', error);
                        updateTrackInfo(true); // Force update to sync state
                    }
                } else {
                    console.warn('⚠️ [DropBeat] Video element not found or invalid position:', {
                        videoFound: !!video,
                        position: message?.data?.position
                    });
                }
                break;
            }
            case 'toggleLike': {
                const button = findElement(selectors.like);
                if (button) {
                    console.log('👍 [DropBeat] Found like button, clicking...');
                    button.click();
                } else {
                    console.warn('️ [DropBeat] Like button not found');
                }
                break;
            }
        }
    } catch (error) {
        console.error('❌ [DropBeat] Error handling command:', error);
    }
}

function getTrackInfo() {
    const video = document.querySelector('video');
    if (!video) {
        console.log('⚠️ [DropBeat] No video element found');
        return null;
    }

    // More specific selectors for YouTube Music
    const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
    const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
    const albumArtElement = document.querySelector('img.ytmusic-player-bar');
    const likeButton = document.querySelector('ytmusic-like-button-renderer');
    
    // Only return track info if we have a title and artist
    const title = titleElement?.textContent?.trim();
    const artist = artistElement?.textContent?.trim();
    if (!title || !artist) {
        console.log('⚠️ [DropBeat] Missing title or artist');
        return null;
    }
    
    // Get the actual video ID from the URL
    const urlParams = new URLSearchParams(window.location.search);
    const videoId = urlParams.get('v');
    console.log('🎵 [DropBeat] Current video ID from URL:', videoId);

    // Track change detection
    const newTrackSignature = `${title}-${artist}`;
    const trackChanged = newTrackSignature !== lastTrackSignature;
    lastTrackSignature = newTrackSignature;
    
    // Always use video ID as track ID if available
    currentTrackId = videoId;
    console.log('🆔 [DropBeat] Track ID:', currentTrackId, 'for track:', title, 'by', artist);

    // Get the album art URL and ensure it's a high-quality version
    let albumArtUrl = albumArtElement?.src;
    if (albumArtUrl) {
        // Replace any existing size parameters with a larger size
        albumArtUrl = albumArtUrl.replace(/=w\d+-h\d+/, '=w500-h500');
    }

    // Enhanced duration and time handling
    let duration = video.duration;
    let currentTime = video.currentTime;
    
    // Handle track transitions
    if (trackChanged) {
        console.log('🔄 [DropBeat] Track changed, handling transition...');
        
        // Reset times if we're in a transition state
        if (currentTime >= duration || !duration || duration === Infinity) {
            console.log('⏱️ [DropBeat] Resetting times during transition');
            currentTime = 0;
            duration = 0;
        }
        
        // Wait for valid duration
        if (duration === 0 || duration === Infinity) {
            console.log('⏳ [DropBeat] Waiting for valid duration...');
            // Try up to 5 times with increasing delays
            for (let i = 0; i < 5; i++) {
                if (video.duration && video.duration !== Infinity) {
                    duration = video.duration;
                    console.log('✅ [DropBeat] Got valid duration:', duration);
                    break;
                }
                console.log('⏳ [DropBeat] Duration not ready, attempt:', i + 1);
                // Add small delay between checks
                new Promise(r => setTimeout(r, 100 * (i + 1)));
            }
        }
    }

    // Ensure times are valid
    duration = (duration && duration !== Infinity) ? duration : 0;
    currentTime = Math.min(Math.max(0, currentTime), duration);

    const trackInfo = {
        id: currentTrackId,
        title: title,
        artist: artist,
        albumArtUrl: albumArtUrl,
        isPlaying: !video.paused,
        currentTime: currentTime,
        duration: duration,
        isLiked: likeButton?.getAttribute('like-status') === 'LIKE'
    };

    console.log('🔍 [DropBeat] Track info:', trackInfo);
    return trackInfo;
}

// Add state preservation
window._dropbeatState = window._dropbeatState || {
    lastTrackInfo: null,
    isConnected: false,
    observers: {},
    initialized: false,
    videoEvents: null
};

// Update timeupdate handling in observePlayer
function observePlayer() {
    console.log('🔍 [DropBeat] Setting up player observers');

    // Preserve previous state if it exists
    if (window._dropbeatState.observers.player) {
        console.log('♻️ [DropBeat] Reusing existing player observer');
        return;
    }

    // Watch for player bar changes
    const playerBar = document.querySelector('ytmusic-player-bar');
    if (playerBar) {
        // Add click listener for manual interactions
        playerBar.addEventListener('click', (event) => {
            // Check if the click was on a control button
            if (event.target.closest('button')) {
                console.log('👆 [DropBeat] Manual player interaction detected');
                // Force state sync after a short delay
                setTimeout(() => {
                    updateTrackInfo(true);
                }, 100);
            }
        });

        const observer = new MutationObserver((mutations) => {
            const hasRelevantChanges = mutations.some(mutation => {
                if (mutation.target.classList.contains('title') || 
                    mutation.target.classList.contains('byline') ||
                    mutation.target.classList.contains('ytmusic-player-bar')) {
                    return true;
                }
                return Array.from(mutation.addedNodes).some(node => 
                    node.classList?.contains('title') || 
                    node.classList?.contains('byline')
                );
            });

            if (hasRelevantChanges) {
                console.log('👁️ [DropBeat] Track info changes detected');
                updateTrackInfo(true);
            }
        });

        observer.observe(playerBar, {
            subtree: true,
            childList: true,
            attributes: true,
            characterData: true
        });
        
        window._dropbeatState.observers.player = observer;
        console.log('✅ [DropBeat] Player bar observer set up');
    }

    // Watch video element with enhanced monitoring
    const video = document.querySelector('video');
    if (video) {
        // Add listeners for manual video interactions
        video.addEventListener('play', () => {
            console.log('👆 [DropBeat] Manual video play detected');
            updateTrackInfo(true);
        });

        video.addEventListener('pause', () => {
            console.log('👆 [DropBeat] Manual video pause detected');
            updateTrackInfo(true);
        });

        // Set up video event listeners
        const videoEvents = {
            play: () => {
                console.log('▶️ [DropBeat] Video play event');
                updateTrackInfo(true);
            },
            pause: () => {
                console.log('⏸️ [DropBeat] Video pause event');
                updateTrackInfo(true);
            },
            seeked: () => {
                console.log('⏩ [DropBeat] Video seek event');
                updateTrackInfo(true);
            },
            timeupdate: () => {
                // More frequent updates for better seek tracking
                if (!window._lastTimeUpdate || Date.now() - window._lastTimeUpdate > 250) {
                    window._lastTimeUpdate = Date.now();
                    updateTrackInfo();
                }
            },
            loadedmetadata: () => {
                console.log('📥 [DropBeat] Video metadata loaded');
                updateTrackInfo(true);
            },
            ended: () => {
                console.log('🔚 [DropBeat] Video ended');
                updateTrackInfo(true);
            }
        };

        // Store event listeners for preservation
        window._dropbeatState.videoEvents = videoEvents;

        // Add all event listeners
        Object.entries(videoEvents).forEach(([event, handler]) => {
            video.addEventListener(event, handler);
        });

        console.log('✅ [DropBeat] Video element listeners set up');
    }
}

// Add this new function to check if YouTube Music is fully ready
async function waitForYTMusic(maxAttempts = 10) {
    console.log('🔄 [DropBeat Debug] Waiting for YouTube Music to be ready');
    
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
        const player = getYTMusicPlayer();
        const video = document.querySelector('video');
        const playerBar = document.querySelector('ytmusic-player-bar');
        
        if (player && video && playerBar) {
            console.log('✅ [DropBeat Debug] YouTube Music is ready');
            return true;
        }
        
        console.log(`⏳ [DropBeat Debug] Waiting for elements (attempt ${attempt + 1}/${maxAttempts})`);
        await new Promise(r => setTimeout(r, 1000));
    }
    
    console.log('❌ [DropBeat Debug] Timeout waiting for YouTube Music');
    return false;
}

// Add URL change detection
const originalPushState = history.pushState;
const originalReplaceState = history.replaceState;

// Intercept pushState
history.pushState = function() {
    console.log('👀 [DropBeat] pushState detected');
    handleUrlChange();
    return originalPushState.apply(this, arguments);
};

// Intercept replaceState
history.replaceState = function() {
    console.log('👀 [DropBeat] replaceState detected');
    handleUrlChange();
    return originalReplaceState.apply(this, arguments);
};

// Handle popstate events
window.addEventListener('popstate', () => {
    console.log('👀 [DropBeat] popstate detected');
    handleUrlChange();
});

// Handle URL changes
async function handleUrlChange() {
    const currentUrl = window.location.href;
    if (currentUrl === navigationState.lastUrl) {
        return;
    }
    
    console.log('🔄 [DropBeat] URL changed:', currentUrl);
    navigationState.lastUrl = currentUrl;
    navigationState.isNavigating = true;
    navigationState.lastNavigationTime = Date.now();
    navigationState.navigationCount++;
    
    // Wait for navigation to settle
    await new Promise(r => setTimeout(r, 500));
    
    try {
        // Check if we need reinitialization
        const isHealthy = await checkContentScriptHealth();
        if (!isHealthy) {
            console.log('⚠️ [DropBeat] Content script needs reinitialization after navigation');
            await initialize(true);
        } else {
            // Even if healthy, we should update observers for the new page
            console.log('✅ [DropBeat] Updating observers for new page');
            setupNavigationObserver();
            observePlayer();
        }
        
        // Force track info update after navigation
        setTimeout(() => {
            updateTrackInfo(true);
        }, 1000);
    } finally {
        navigationState.isNavigating = false;
    }
}

// Update initialize function to be more robust
async function initialize(forceReinit = false) {
    console.log('%c[DropBeat] 🎯 INITIALIZE CALLED', 'background: #00ff00; color: black; font-size: 15px; padding: 5px;', {
        forceReinit,
        hasExistingState: window._dropbeatState.initialized,
        navigationCount: navigationState.navigationCount
    });

    // If we're currently navigating, wait a bit
    if (navigationState.isNavigating) {
        console.log('⏳ [DropBeat] Waiting for navigation to complete');
        await new Promise(r => setTimeout(r, 1000));
    }

    // If we already have a working state and it's not a forced reinit, skip
    if (window._dropbeatState.initialized && !forceReinit) {
        console.log('♻️ [DropBeat] Using existing state');
        return;
    }

    try {
        // Wait for YouTube Music to be ready with increased timeout for first load
        const isFirstLoad = navigationState.navigationCount === 0;
        const timeout = isFirstLoad ? 15 : 10;
        const isReady = await waitForYTMusic(timeout);
        
        if (!isReady) {
            console.warn('⚠️ [DropBeat] YouTube Music not ready, retrying in 2s');
            setTimeout(() => initialize(true), 2000);
            return;
        }

        // Clean up existing observers
        if (window._dropbeatState.observers.player) {
            window._dropbeatState.observers.player.disconnect();
        }
        if (window._dropbeatState.observers.navigation) {
            window._dropbeatState.observers.navigation.disconnect();
        }

        // Set up observers and listeners
        observePlayer();
        setupNavigationObserver();
        setupDurationChangeListener();  // Add duration change listener
        
        // Mark as initialized
        window._dropbeatState.initialized = true;
        youtubeMusiceReady = true;
        
        // Initial track info update
        updateTrackInfo(true);
        
        console.log('✅ [DropBeat] Initialization complete');
    } catch (error) {
        console.error('❌ [DropBeat] Error during initialization:', error);
        // Retry initialization with backoff
        setTimeout(() => initialize(true), 2000);
    }
}

// Update health check to be more lenient during navigation
async function checkContentScriptHealth() {
    try {
        // If we're navigating, be more lenient with health checks
        if (navigationState.isNavigating) {
            console.log('⏳ [DropBeat] Health check during navigation - being lenient');
            const video = document.querySelector('video');
            const playerBar = document.querySelector('ytmusic-player-bar');
            return !!(video && playerBar);
        }
        
        // Regular health check logic...
        // ... (keep existing health check code)
        
    } catch (error) {
        console.error('❌ [DropBeat] Health check error:', error);
        return false;
    }
}

// Update the start logic to handle async initialize
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => initialize());
} else {
    initialize();
}

// Update track info handling
function updateTrackInfo(force = false) {
    const trackInfo = getTrackInfo();
    if (!trackInfo) return;

    // Check against last state
    const lastInfo = window._dropbeatState.lastTrackInfo;
    const hasChanged = !lastInfo || 
        trackInfo.id !== lastInfo.id ||
        trackInfo.title !== lastInfo.title ||
        trackInfo.artist !== lastInfo.artist ||
        trackInfo.isPlaying !== lastInfo.isPlaying ||
        Math.abs(trackInfo.currentTime - (lastInfo.currentTime || 0)) > 0.25 || // More sensitive time tracking
        Math.abs(trackInfo.duration - (lastInfo.duration || 0)) > 0.25 || // Add duration change detection
        trackInfo.isLiked !== lastInfo.isLiked;

    if (force || hasChanged) {
        window._dropbeatState.lastTrackInfo = trackInfo;
        sendTrackInfo(trackInfo);
    }
}

// Enhanced message sending with retry and confirmation
async function sendMessageToServiceWorker(message, maxRetries = 3) {
    let attempt = 0;
    while (attempt < maxRetries) {
        try {
            const response = await chrome.runtime.sendMessage(message);
            if (response?.error) {
                console.warn('⚠️ [DropBeat] Service worker reported error:', response.error);
                throw new Error(response.error);
            }
            return response;
        } catch (error) {
            attempt++;
            console.error(`❌ [DropBeat] Failed to send message to service worker (attempt ${attempt}/${maxRetries}):`, error);
            if (error.message.includes('Extension context invalidated')) {
                console.log('🔄 [DropBeat] Extension context invalid, attempting recovery');
                // Force reinitialize on context invalidation
                await initialize(true);
            }
            if (attempt === maxRetries) {
                throw error;
            }
            // Exponential backoff
            await new Promise(r => setTimeout(r, Math.min(1000 * Math.pow(2, attempt), 5000)));
        }
    }
}

// Update sendTrackInfo to use the enhanced message sending
function sendTrackInfo(trackInfo) {
    console.log('📤 [DropBeat] Sending track info:', trackInfo);

    sendMessageToServiceWorker({
        type: 'TRACK_INFO',
        data: trackInfo
    }).then(response => {
        if (response?.sent) {
            console.log('✅ [DropBeat] Track info sent successfully');
            // Update last successful sync time
            window._dropbeatState.lastSuccessfulSync = Date.now();
        } else {
            console.warn('⚠️ [DropBeat] Failed to send track info');
            // Schedule a retry if needed
            if (!window._dropbeatState.retryTimeout) {
                window._dropbeatState.retryTimeout = setTimeout(() => {
                    window._dropbeatState.retryTimeout = null;
                    updateTrackInfo(true);
                }, 2000);
            }
        }
    }).catch(error => {
        console.error('❌ [DropBeat] Error sending track info:', error);
        // Handle disconnection if needed
        if (error.message.includes('Extension context invalidated') || 
            error.message.includes('Could not establish connection')) {
            window._dropbeatState.isConnected = false;
            // Attempt recovery
            initialize(true);
        }
    });
}

// Add connection health monitoring
setInterval(async () => {
    if (!window._dropbeatState.isConnected) {
        return;
    }
    
    const timeSinceLastSync = Date.now() - (window._dropbeatState.lastSuccessfulSync || 0);
    if (timeSinceLastSync > 10000) { // 10 seconds
        console.warn('⚠️ [DropBeat] No successful sync for', Math.round(timeSinceLastSync/1000), 'seconds');
        try {
            // Check service worker connection
            const response = await sendMessageToServiceWorker({ type: 'PING' });
            if (!response?.pong) {
                throw new Error('Invalid ping response');
            }
            // If we get here, connection is good but we might have missed updates
            updateTrackInfo(true);
        } catch (error) {
            console.error('❌ [DropBeat] Connection check failed:', error);
            // Force reconnection attempt
            window._dropbeatState.isConnected = false;
            initialize(true);
        }
    }
}, 5000);

// Get initial connection status
chrome.runtime.sendMessage({ type: 'GET_CONNECTION_STATUS' }, (response) => {
    if (response) {
        window._dropbeatState.isConnected = response.isConnected;
        console.log('🔌 [DropBeat] Initial connection status:', window._dropbeatState.isConnected);
    }
});

// Start when page is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
} else {
    initialize();
}

// Add this new function
function showPlaylistNotification() {
    // Create notification element if it doesn't exist
    let notification = document.getElementById('dropbeat-notification');
    if (!notification) {
        notification = document.createElement('div');
        notification.id = 'dropbeat-notification';
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 12px 24px;
            border-radius: 8px;
            z-index: 9999;
            font-family: 'YouTube Sans', sans-serif;
            display: flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        `;
        document.body.appendChild(notification);
    }
    
    notification.innerHTML = '🎵 Click the play button to start the playlist';
    
    // Auto-hide after 5 seconds
    setTimeout(() => {
        if (notification && notification.parentNode) {
            notification.parentNode.removeChild(notification);
        }
    }, 5000);
}

// Add these helper functions after your existing selectors
function getYTMusicPlayer() {
    return window.ytmusic?.player_ || 
           document.querySelector('ytmusic-player')?.player_ ||
           document.querySelector('#movie_player');
}

// Enhanced playlist handling
async function handlePlaylistPlayback(timeout = 8000) {
    console.log('🎵 [DropBeat Debug] Starting handlePlaylistPlayback');
    
    try {
        // First, check if we're already playing
        const video = document.querySelector('video');
        if (video && !video.paused) {
            console.log('✅ [DropBeat Debug] Playlist already playing');
            return true;
        }

        // Try using YouTube Music's internal player first
        const player = getYTMusicPlayer();
        if (player) {
            console.log('🎯 [DropBeat Debug] Found YouTube Music player, attempting playback');
            try {
                // Try different methods to start playback
                if (typeof player.playVideo === 'function') {
                    await player.playVideo();
                } else if (typeof player.play === 'function') {
                    await player.play();
                }
                
                // Wait to verify playback started
                await new Promise(r => setTimeout(r, 1000));
                const videoAfterPlay = document.querySelector('video');
                if (videoAfterPlay && !videoAfterPlay.paused) {
                    console.log('✅ [DropBeat Debug] Playlist playback started via player API');
                    return true;
                }
            } catch (error) {
                console.log('⚠️ [DropBeat Debug] Player API attempt failed:', error);
            }
        }

        // Fallback to DOM method if player API fails
        console.log('🔄 [DropBeat Debug] Falling back to DOM method');
        const playButton = findElement(selectors.playlistControls.playButton);
        if (playButton) {
            console.log('🎯 [DropBeat Debug] Found play button, attempting click');
            playButton.click();
            
            // Wait to verify playback started
            await new Promise(r => setTimeout(r, 2000));
            const videoAfterClick = document.querySelector('video');
            if (videoAfterClick && !videoAfterClick.paused) {
                console.log('✅ [DropBeat Debug] Playlist playback started via button click');
                return true;
            }
        }

        // If we reach here, both methods failed
        console.log('❌ [DropBeat Debug] All playback attempts failed');
        return false;
    } catch (error) {
        console.error('❌ [DropBeat Debug] Error in handlePlaylistPlayback:', error);
        return false;
    }
}

// Helper function to ensure YouTube Music is ready
function ensureYouTubeMusicReady(timeout = 10000) {
    return new Promise((resolve) => {
        if (youtubeMusiceReady) {
            resolve(true);
            return;
        }

        const startTime = Date.now();
        const checkInterval = setInterval(() => {
            // Check for critical YouTube Music elements
            const playerBar = document.querySelector('ytmusic-player-bar');
            const player = document.querySelector('#movie_player');
            const content = document.querySelector('#content');

            if (playerBar && player && content) {
                clearInterval(checkInterval);
                youtubeMusiceReady = true;
                resolve(true);
                return;
            }

            if (Date.now() - startTime > timeout) {
                clearInterval(checkInterval);
                console.warn('⚠️ [DropBeat] Timeout waiting for YouTube Music');
                resolve(false);
            }
        }, 100);
    });
}

// Enhanced duration change listener
function setupDurationChangeListener() {
    const video = document.querySelector('video');
    if (video) {
        video.addEventListener('durationchange', () => {
            const newDuration = video.duration;
            console.log('⏱️ [DropBeat] Duration changed:', newDuration);
            
            // Handle invalid states
            if (!newDuration || newDuration === Infinity) {
                console.log('⚠️ [DropBeat] Invalid duration, waiting...');
                return;
            }
            
            // Check for transition state
            if (video.currentTime > newDuration) {
                console.log('🔄 [DropBeat] Detected transition state, forcing update');
                updateTrackInfo(true);
            } else {
                // Normal duration update
                updateTrackInfo(true);
            }
        });
        
        // Add ended event listener for better transition handling
        video.addEventListener('ended', () => {
            console.log('🔚 [DropBeat] Track ended, preparing for transition');
            // Force an update with reset times
            setTimeout(() => {
                updateTrackInfo(true);
            }, 100);
        });
    }
}