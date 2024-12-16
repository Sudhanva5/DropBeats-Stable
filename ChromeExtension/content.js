console.log('🎵 [DropBeat] Content script loaded for YouTube Music');

let isConnected = false;
let lastTrackInfo = null;
let currentTrackId = null;
let lastTrackSignature = null;

// Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📥 [DropBeat] Content received message:', message);

    try {
        if (message.type === 'CONNECTION_STATUS') {
            const oldState = isConnected;
            isConnected = message.status.isConnected;
            console.log('🔌 [DropBeat] Connection status updated:', isConnected);
            
            // If we just got connected, send initial track info
            if (!oldState && isConnected) {
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

function findElement(selectors) {
    for (const selector of selectors) {
        const element = document.querySelector(selector);
        if (element) return element;
    }
    return null;
}

function handleCommand(command, message) {
    console.log('🎮 [DropBeat] Handling command:', command, 'with full message:', message);
    
    // Define multiple selectors for each control, ordered by reliability
    const selectors = {
        playPause: [
            // By aria-label
            'button[aria-label*="Play"], button[aria-label*="Pause"]',
            // By class
            '.play-pause-button',
            // By role and title
            'button[role="button"][title*="Play"], button[role="button"][title*="Pause"]',
            // By data attribute
            '[data-testid="play-pause-button"]',
            // Generic player controls
            '.ytmusic-player-bar button[aria-label*="Play"], .ytmusic-player-bar button[aria-label*="Pause"]'
        ],
        next: [
            'button[aria-label*="Next"]',
            '.next-button',
            'button[role="button"][title*="Next"]',
            '[data-testid="next-button"]',
            '.ytmusic-player-bar button[aria-label*="Next"]'
        ],
        previous: [
            'button[aria-label*="Previous"]',
            '.previous-button',
            'button[role="button"][title*="Previous"]',
            '[data-testid="previous-button"]',
            '.ytmusic-player-bar button[aria-label*="Previous"]'
        ],
        like: [
            'ytmusic-like-button-renderer',
            'button[aria-label*="like"]',
            '[data-testid="like-button-renderer"]'
        ]
    };

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
            }, 100); // Reduced polling frequency
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
            const checkInterval = setInterval(() => {
                const video = document.querySelector('video');
                const isNowPlaying = !video?.paused;
                
                // First verify the track hasn't changed
                if (!verifyTrackUnchanged(originalSignature)) {
                    clearInterval(checkInterval);
                    resolve({ changed: false, reason: 'track_changed' });
                    return;
                }
                
                if (isNowPlaying !== wasPlaying) {
                    stabilityCounter++;
                    // Wait for the state to be stable for at least 2 checks
                    if (stabilityCounter >= 2) {
                        clearInterval(checkInterval);
                        // Add a small delay to let YouTube Music stabilize
                        setTimeout(() => resolve({ changed: true, isPlaying: isNowPlaying }), 100);
                    }
                } else {
                    stabilityCounter = 0;
                }

                if (Date.now() - startTime > timeout) {
                    clearInterval(checkInterval);
                    resolve({ changed: false, reason: 'timeout' });
                }
            }, 100);
        });
    };
    
    try {
        switch (command) {
            case 'play':
            case 'pause': {
                const button = findElement(selectors.playPause);
                if (button) {
                    console.log('▶️ [DropBeat] Found play/pause button, clicking...');
                    const video = document.querySelector('video');
                    const wasPlaying = !video?.paused;
                    
                    // Get current track signature before clicking
                    const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                    const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                    const originalSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
                    
                    // Add a small delay before clicking to let any previous operations complete
                    setTimeout(() => {
                        // Click the button
                        button.click();
                        
                        // Wait for the video state to actually change
                        if (video) {
                            waitForPlayStateChange(wasPlaying, originalSignature).then(result => {
                                if (result.changed) {
                                    // Verify one final time that track hasn't changed
                                    if (verifyTrackUnchanged(originalSignature)) {
                                        setTimeout(() => {
                                            const updatedTrackInfo = {
                                                ...lastTrackInfo,
                                                isPlaying: result.isPlaying
                                            };
                                            lastTrackInfo = updatedTrackInfo;
                                            chrome.runtime.sendMessage({
                                                type: 'TRACK_INFO',
                                                data: updatedTrackInfo
                                            });
                                        }, 100);
                                    } else {
                                        console.warn('⚠️ [DropBeat] Track changed during play/pause operation');
                                        updateTrackInfo(true); // Force update with new track info
                                    }
                                } else {
                                    if (result.reason === 'track_changed') {
                                        console.warn('⚠️ [DropBeat] Track changed unexpectedly during play/pause');
                                        updateTrackInfo(true); // Force update with new track info
                                    } else {
                                        console.warn('⚠️ [DropBeat] Play state did not change as expected');
                                    }
                                }
                            });
                        }
                    }, 100);
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
                    console.log('❤️ [DropBeat] Found like button, clicking...');
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
    const albumArtElement = document.querySelector('.ytmusic-player-bar img.image.style-scope.ytmusic-player-bar');
    const likeButton = document.querySelector('ytmusic-like-button-renderer');
    
    const title = titleElement?.textContent?.trim() || 'No Track Playing';
    const artist = artistElement?.textContent?.trim() || 'Unknown Artist';
    
    // Generate a unique ID based on title and artist if it's a new track
    const trackSignature = `${title}-${artist}`;
    if (trackSignature !== lastTrackSignature) {
        currentTrackId = crypto.randomUUID();
        lastTrackSignature = trackSignature;
    }

    console.log('🔍 [DropBeat] Found elements:', {
        title: title,
        artist: artist,
        albumArt: albumArtElement?.src,
        video: video ? 'Yes' : 'No',
        isPlaying: !video.paused,
        currentTime: video.currentTime,
        duration: video.duration
    });

    return {
        id: currentTrackId,
        title: title,
        artist: artist,
        albumArt: albumArtElement?.src,
        isPlaying: !video.paused,
        currentTime: video.currentTime,
        duration: video.duration || 0,
        isLiked: likeButton?.getAttribute('like-status') === 'LIKE'
    };
}

function updateTrackInfo(force = false, retryCount = 0) {
    if (!isConnected) {
        console.log('⏳ [DropBeat] Not connected, skipping track update');
        return;
    }

    const trackInfo = getTrackInfo();
    if (!trackInfo) return;

    // Send if forced or if info has changed
    if (force || JSON.stringify(trackInfo) !== JSON.stringify(lastTrackInfo)) {
        console.log('🎵 [DropBeat] Sending track info:', trackInfo);
        lastTrackInfo = trackInfo;

        chrome.runtime.sendMessage({
            type: 'TRACK_INFO',
            data: trackInfo
        }, response => {
            if (response?.sent) {
                console.log('✅ [DropBeat] Track info sent successfully');
            } else {
                console.warn('⚠️ [DropBeat] Failed to send track info');
                // Retry up to 2 times with increasing delay
                if (retryCount < 2) {
                    const delay = Math.pow(2, retryCount) * 500; // 500ms, then 1000ms
                    console.log(`🔄 [DropBeat] Retrying in ${delay}ms (attempt ${retryCount + 1}/2)`);
                    setTimeout(() => {
                        updateTrackInfo(force, retryCount + 1);
                    }, delay);
                }
            }
        });
    }
}

function observePlayer() {
    console.log('👀 [DropBeat] Setting up player observers');

    // Watch for player bar changes
    const playerBar = document.querySelector('ytmusic-player-bar');
    if (playerBar) {
        const observer = new MutationObserver((mutations) => {
            console.log('👁️ [DropBeat] Player changes detected');
            updateTrackInfo();
        });

        observer.observe(playerBar, {
            subtree: true,
            childList: true,
            attributes: true
        });
        console.log('✅ [DropBeat] Player bar observer set up');
    }

    // Watch video element
    const video = document.querySelector('video');
    if (video) {
        video.addEventListener('play', () => {
            console.log('▶️ [DropBeat] Video play event');
            updateTrackInfo(true);
        });

        video.addEventListener('pause', () => {
            console.log('⏸️ [DropBeat] Video pause event');
            updateTrackInfo(true);
        });

        video.addEventListener('seeked', () => {
            console.log('⏩ [DropBeat] Video seek event');
            updateTrackInfo(true);
        });

        console.log('✅ [DropBeat] Video element listeners set up');
    }
}

// Start observing when page is ready
function initialize() {
    console.log('🚀 [DropBeat] Initializing content script');
    
    // Check if we're already on YouTube Music
    if (document.querySelector('ytmusic-player-bar')) {
        observePlayer();
        updateTrackInfo(true);
    } else {
        // Wait for player to be ready
        const observer = new MutationObserver((mutations, obs) => {
            if (document.querySelector('ytmusic-player-bar')) {
                console.log('✅ [DropBeat] Player detected, starting observation');
                obs.disconnect();
                observePlayer();
                updateTrackInfo(true);
            }
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }
}

// Get initial connection status
chrome.runtime.sendMessage({ type: 'GET_CONNECTION_STATUS' }, (response) => {
    if (response) {
        isConnected = response.isConnected;
        console.log('🔌 [DropBeat] Initial connection status:', isConnected);
    }
});

// Start when page is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
} else {
    initialize();
}