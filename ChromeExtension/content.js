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
            'button[aria-label*="Play"], button[aria-label*="Pause"]',
            '.play-pause-button',
            'button[role="button"][title*="Play"], button[role="button"][title*="Pause"]',
            '[data-testid="play-pause-button"]',
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
            case 'play': {
                // Check if we have a URL to navigate to (for collections)
                if (message?.data?.url) {
                    console.log('🔀 [DropBeat] Navigating to collection:', message.data.url);
                    window.location.href = message.data.url;
                    return;
                }
                
                // Check if we have a song ID to play
                if (message?.data?.id) {
                    console.log('🎵 [DropBeat] Playing song by ID:', message.data.id);
                    
                    // Get current URL and video ID
                    const currentUrl = new URL(window.location.href);
                    const currentVideoId = currentUrl.searchParams.get('v');
                    console.log('🔍 [DropBeat] Current video ID:', currentVideoId);
                    
                    // If we're already on the correct video, just ensure it's playing
                    if (currentVideoId === message.data.id) {
                        console.log('✅ [DropBeat] Already on correct video, ensuring playback');
                        const video = document.querySelector('video');
                        const playButton = findElement(selectors.playPause);
                        
                        if (video && video.paused) {
                            console.log('▶️ [DropBeat] Starting playback of current video');
                            try {
                                video.play();
                            } catch (error) {
                                console.log('⚠️ [DropBeat] video.play() failed, trying button click');
                                playButton?.click();
                            }
                        }
                        return;
                    }

                    // Navigate to the song
                    const songUrl = `https://music.youtube.com/watch?v=${message.data.id}`;
                    console.log('🔀 [DropBeat] Navigating to:', songUrl);
                    
                    // Get current track signature before navigating
                    const titleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                    const artistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                    const currentSignature = `${titleElement?.textContent?.trim() || ''}-${artistElement?.textContent?.trim() || ''}`;
                    
                    // Set up a mutation observer before navigation
                    const observer = new MutationObserver((mutations, obs) => {
                        const video = document.querySelector('video');
                        const playButton = findElement(selectors.playPause);
                        const newTitleElement = document.querySelector('.ytmusic-player-bar .title.style-scope.ytmusic-player-bar');
                        const newArtistElement = document.querySelector('.ytmusic-player-bar .byline.style-scope.ytmusic-player-bar');
                        const newSignature = `${newTitleElement?.textContent?.trim() || ''}-${newArtistElement?.textContent?.trim() || ''}`;
                        
                        // Check if we have all elements and the track has changed
                        if (video && playButton && newSignature !== currentSignature && newTitleElement?.textContent?.trim()) {
                            console.log('👀 [DropBeat] New track detected after navigation');
                            
                            // Wait a bit for everything to load
                            setTimeout(async () => {
                                try {
                                    // Force update track info first
                                    updateTrackInfo(true);
                                    
                                    // Try to start playback
                                    console.log('▶️ [DropBeat] Starting playback after navigation');
                                    try {
                                        await video.play();
                                        console.log('✅ [DropBeat] Playback started via video.play()');
                                    } catch (error) {
                                        console.log('⚠️ [DropBeat] video.play() failed, trying button click');
                                        playButton.click();
                                        // Double check if we need to click again
                                        setTimeout(() => {
                                            if (video.paused) {
                                                console.log('⚠️ [DropBeat] Still paused, clicking again');
                                                playButton.click();
                                            }
                                        }, 500);
                                    }
                                    
                                    // Force update track info again after playback starts
                                    setTimeout(() => {
                                        updateTrackInfo(true);
                                    }, 1000);
                                } catch (error) {
                                    console.error('❌ [DropBeat] Error starting playback:', error);
                                }
                            }, 1000);
                            
                            // Disconnect the observer once we've handled the playback
                            obs.disconnect();
                        }
                    });
                    
                    // Start observing for changes
                    observer.observe(document.body, {
                        childList: true,
                        subtree: true
                    });
                    
                    // Navigate to the song
                    window.location.href = songUrl;
                    
                    return;
                }
                
                // If no ID, just toggle play/pause
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
            case 'pause': {
                const button = findElement(selectors.playPause);
                if (button) {
                    console.log('⏸️ [DropBeat] Found play/pause button, clicking...');
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

    // Always use video ID as track ID if available
    currentTrackId = videoId;
    lastTrackSignature = `${title}-${artist}`;
    console.log('🆔 [DropBeat] Track ID:', currentTrackId, 'for track:', title, 'by', artist);

    // Get the album art URL and ensure it's a high-quality version
    let albumArtUrl = albumArtElement?.src;
    if (albumArtUrl) {
        // Replace any existing size parameters with a larger size
        albumArtUrl = albumArtUrl.replace(/=w\d+-h\d+/, '=w500-h500');
    }

    const trackInfo = {
        id: currentTrackId,
        title: title,
        artist: artist,
        albumArtUrl: albumArtUrl,
        isPlaying: !video.paused,
        currentTime: video.currentTime,
        duration: video.duration || 0,
        isLiked: likeButton?.getAttribute('like-status') === 'LIKE'
    };

    console.log('🔍 [DropBeat] Track info:', trackInfo);
    return trackInfo;
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
                console.warn('⚠��� [DropBeat] Failed to send track info');
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