console.log('🎵 [DropBeat] Background script loaded');

class WebSocketManager {
    constructor() {
        this.ws = null;
        this.isConnecting = false;
        this.reconnectTimer = null;
        this.pingInterval = null;
        this.reconnectAttempts = 0;
        this.MAX_RECONNECT_ATTEMPTS = 10;
        this.INITIAL_RECONNECT_DELAY = 1000;
        this.MAX_RECONNECT_DELAY = 30000;
        this.PING_INTERVAL = 5000;
        this.lastPongReceived = Date.now();
        this.PONG_TIMEOUT = 10000;
        
        this.state = {
            isConnected: false,
            lastError: null,
            reconnecting: false,
            nextReconnectTime: null
        };
        
        // Bind methods
        this.checkConnection = this.checkConnection.bind(this);
        
        // Start connection checker
        setInterval(this.checkConnection, this.PING_INTERVAL);
        
        console.log('🎵 [DropBeat] WebSocket Manager initialized');
    }
    
    checkConnection() {
        if (this.ws?.readyState === WebSocket.OPEN) {
            const timeSinceLastPong = Date.now() - this.lastPongReceived;
            if (timeSinceLastPong > this.PONG_TIMEOUT) {
                console.log('⚠️ [DropBeat] Connection seems dead, last pong was', timeSinceLastPong, 'ms ago');
                this.handleDisconnection('Connection timeout - no pong received');
            }
        }
    }

    async connect() {
        if (this.isConnecting || this.ws?.readyState === WebSocket.OPEN) {
            console.log('⏳ [DropBeat] Connection already in progress or established');
            return;
        }

        this.isConnecting = true;
        console.log('🔌 [DropBeat] Initiating connection...');

        try {
            await this.cleanup();
            
            return new Promise((resolve, reject) => {
                try {
                    this.ws = new WebSocket('ws://localhost:8089');
                    console.log('📡 [DropBeat] WebSocket created');

                    const timeout = setTimeout(() => {
                        console.log('⚠️ [DropBeat] Connection attempt timed out');
                        this.ws.close();
                        reject(new Error('Connection timeout'));
                    }, 5000);

                    this.ws.onopen = () => {
                        clearTimeout(timeout);
                        console.log('🎉 [DropBeat] Connection established');
                        this.handleOpen();
                        resolve();
                    };

                    this.ws.onclose = (event) => {
                        clearTimeout(timeout);
                        console.log('🔴 [DropBeat] Connection closed:', event);
                        this.handleDisconnection('Connection closed: ' + event.code);
                        reject(new Error('Connection closed'));
                    };

                    this.ws.onerror = (error) => {
                        clearTimeout(timeout);
                        console.error('❌ [DropBeat] Connection error:', error);
                        reject(error);
                    };

                    this.ws.onmessage = this.handleMessage.bind(this);

                } catch (error) {
                    console.error('❌ [DropBeat] Error creating WebSocket:', error);
                    reject(error);
                }
            });

        } catch (error) {
            console.error('❌ [DropBeat] Connection error:', error);
            this.handleDisconnection(error.message);
            throw error;
        } finally {
            this.isConnecting = false;
        }
    }

    async cleanup() {
        console.log('🧹 [DropBeat] Cleaning up...');
        
        if (this.pingInterval) {
            clearInterval(this.pingInterval);
            this.pingInterval = null;
        }

        if (this.ws) {
            try {
                this.ws.close();
            } catch (error) {
                console.log('⚠️ [DropBeat] Error closing WebSocket:', error);
            }
            this.ws = null;
        }
    }

    handleOpen() {
        console.log('🎉 [DropBeat] Handling successful connection');
        this.reconnectAttempts = 0;
        this.state.isConnected = true;
        this.state.lastError = null;
        this.state.reconnecting = false;
        this.state.nextReconnectTime = null;
        this.lastPongReceived = Date.now();
        
        this.startPingInterval();
        this.broadcastState();
        
        // Send immediate ping
        this.sendPing();
    }

    startPingInterval() {
        console.log('⏰ [DropBeat] Starting ping interval');
        if (this.pingInterval) {
            clearInterval(this.pingInterval);
        }
        this.pingInterval = setInterval(() => this.sendPing(), this.PING_INTERVAL);
    }

    sendPing() {
        if (this.ws?.readyState === WebSocket.OPEN) {
            const ping = { type: 'PING', timestamp: Date.now() };
            console.log('📤 [DropBeat] Sending ping:', ping);
            try {
                this.ws.send(JSON.stringify(ping));
            } catch (error) {
                console.error('❌ [DropBeat] Error sending ping:', error);
                this.handleDisconnection('Failed to send ping');
            }
        }
    }

    handleMessage(event) {
        try {
            const message = JSON.parse(event.data);
            console.log('📥 [DropBeat] WebSocket message received:', message);
            
            if (message.type === 'PONG') {
                this.lastPongReceived = Date.now();
                console.log('✅ [DropBeat] Pong received');
            } else if (message.type === 'COMMAND') {
                console.log('🎮 [DropBeat] Command received:', message.command);
                this.forwardCommandToYouTubeMusic(message);
            }
        } catch (error) {
            console.error('❌ [DropBeat] Failed to parse message:', error);
        }
    }

    async forwardCommandToYouTubeMusic(message) {
        try {
            // Find all YouTube Music tabs
            const tabs = await chrome.tabs.query({ url: '*://music.youtube.com/*' });
            
            if (tabs.length === 0) {
                console.log('⚠️ [DropBeat] No YouTube Music tab found');
                // If it's a request to open YouTube Music or no tab exists, create one
                if (message.command === 'openYouTubeMusic' || ['play', 'pause', 'next', 'previous'].includes(message.command)) {
                    console.log('🎵 [DropBeat] Opening new YouTube Music tab');
                    const newTab = await chrome.tabs.create({ url: 'https://music.youtube.com', active: true });
                    // Wait for the tab to load and content script to be ready
                    await new Promise(resolve => setTimeout(resolve, 3000));
                    return;
                }
                return;
            }

            // Try to find an active YouTube Music tab first
            let targetTab = tabs.find(tab => tab.active) || tabs[0];
            
            // Ensure content script is healthy
            const isScriptReady = await ensureContentScript(targetTab.id);
            if (!isScriptReady) {
                console.log('⚠️ [DropBeat] Content script not ready after injection attempts');
                return;
            }

            // Forward the command
            console.log('📤 [DropBeat] Forwarding command to tab:', targetTab.id);
            await chrome.tabs.sendMessage(targetTab.id, message);
            console.log('✅ [DropBeat] Command forwarded successfully');
        } catch (error) {
            console.error('❌ [DropBeat] Error forwarding command:', error);
        }
    }

    handleDisconnection(reason) {
        console.log('🔴 [DropBeat] Handling disconnection:', reason);
        
        this.cleanup();
        
        this.state.isConnected = false;
        this.state.lastError = reason;
        this.state.reconnecting = true;
        
        this.broadcastState();
        this.scheduleReconnect();
    }

    scheduleReconnect() {
        if (this.reconnectAttempts >= this.MAX_RECONNECT_ATTEMPTS) {
            console.log('❌ [DropBeat] Max reconnection attempts reached');
            this.state.reconnecting = false;
            this.state.lastError = 'Max reconnection attempts reached';
            this.broadcastState();
            return;
        }

        const delay = Math.min(
            this.INITIAL_RECONNECT_DELAY * Math.pow(2, this.reconnectAttempts),
            this.MAX_RECONNECT_DELAY
        );
        
        this.reconnectAttempts++;
        this.state.nextReconnectTime = Date.now() + delay;
        
        console.log(`🔄 [DropBeat] Scheduling reconnect attempt ${this.reconnectAttempts} in ${delay}ms`);
        
        setTimeout(async () => {
            try {
                await this.connect();
            } catch (error) {
                console.log('❌ [DropBeat] Reconnection failed:', error);
            }
        }, delay);
    }

    broadcastState() {
        console.log('📢 [DropBeat] Broadcasting state:', this.state);
        chrome.runtime.sendMessage({
            type: 'CONNECTION_STATUS',
            status: this.state
        }).catch(() => {});
    }

    getState() {
        return this.state;
    }
}

// Create instance
const wsManager = new WebSocketManager();

// Handle messages
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📥 [DropBeat] Chrome message received:', message);
    
    switch (message.type) {
        case 'GET_CONNECTION_STATUS':
            sendResponse(wsManager.getState());
            break;
        case 'TRACK_INFO':
            if (wsManager.ws?.readyState === WebSocket.OPEN) {
                try {
                    wsManager.ws.send(JSON.stringify(message));
                    console.log('✅ [DropBeat] Track info forwarded to WebSocket');
                    sendResponse({ sent: true });
                } catch (error) {
                    console.error('❌ [DropBeat] Error sending track info:', error);
                    sendResponse({ sent: false, error: error.message });
                }
            } else {
                console.log('⚠️ [DropBeat] WebSocket not connected, track info not sent');
                sendResponse({ sent: false, error: 'Not connected' });
            }
            break;
        default:
            console.log('⚠️ [DropBeat] Unknown message type:', message.type);
            sendResponse({ error: 'Unknown message type' });
    }
    
    return true; // Keep the message channel open for async response
});

// Start connection
console.log('🚀 [DropBeat] Starting WebSocket Manager');
wsManager.connect().catch(error => {
    console.error('❌ [DropBeat] Initial connection failed:', error);
});

// Add navigation state tracking
let navigationState = {
    lastNavigationTime: 0,
    pendingNavigations: new Set(),
    debounceTimeout: null
};

// Update navigation handling with debouncing
chrome.webNavigation.onHistoryStateUpdated.addListener(async (details) => {
    if (details.url.includes('music.youtube.com')) {
        console.log('🔄 [DropBeat] YouTube Music navigation detected:', details.url);
        
        // Clear any pending debounce timeout
        if (navigationState.debounceTimeout) {
            clearTimeout(navigationState.debounceTimeout);
        }
        
        // Add this navigation to pending set
        navigationState.pendingNavigations.add(details.tabId);
        
        // Debounce the navigation handling
        navigationState.debounceTimeout = setTimeout(async () => {
            try {
                // Process all pending navigations
                for (const tabId of navigationState.pendingNavigations) {
                    // Wait for the page to settle
                    await new Promise(r => setTimeout(r, 1000));
                    
                    // Check tab still exists
                    try {
                        const tab = await chrome.tabs.get(tabId);
                        if (!tab?.url?.includes('music.youtube.com')) {
                            continue;
                        }
                    } catch (error) {
                        console.log('⚠️ [DropBeat] Tab no longer exists:', tabId);
                        continue;
                    }
                    
                    // Ensure content script is healthy
                    const isHealthy = await ensureContentScript(tabId);
                    
                    if (isHealthy) {
                        // Try to notify content script, but don't wait for response
                        chrome.tabs.sendMessage(tabId, {
                            type: 'NAVIGATION_UPDATE',
                            url: details.url
                        }).catch(() => {
                            // Ignore errors from message sending
                            console.log('ℹ️ [DropBeat] Navigation update notification skipped');
                        });
                    }
                }
            } finally {
                // Clear pending navigations
                navigationState.pendingNavigations.clear();
            }
        }, 500); // Debounce for 500ms
        
        navigationState.lastNavigationTime = Date.now();
    }
});

// Add tab update handling
chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
    if (tab.url?.includes('music.youtube.com') && changeInfo.status === 'complete') {
        console.log('🔄 [DropBeat] YouTube Music tab updated:', tab.url);
        await ensureContentScript(tabId);
    }
});

// Add these new functions for enhanced script management
async function checkContentScriptHealth(tabId) {
    try {
        const response = await chrome.tabs.sendMessage(tabId, { 
            type: 'HEALTH_CHECK',
            timestamp: Date.now()
        });
        
        // Check if we got a valid response
        if (!response) {
            console.log('⚠️ [DropBeat] No health check response');
            return false;
        }
        
        // Check if the response is recent enough
        const responseTime = Date.now() - response.timestamp;
        if (responseTime > 5000) { // 5 seconds threshold
            console.log('⚠️ [DropBeat] Health check response too old:', responseTime, 'ms');
            return false;
        }
        
        // Check if all required elements are present
        const hasAllElements = response.elements?.hasVideo && 
                             response.elements?.hasPlayerBar && 
                             response.elements?.hasPlayer;
                             
        if (!hasAllElements) {
            console.log('⚠️ [DropBeat] Missing required elements:', response.elements);
            return false;
        }
        
        return response.healthy === true;
    } catch (error) {
        console.log('❌ [DropBeat] Health check failed:', error);
        return false;
    }
}

async function ensureContentScript(tabId) {
    console.log('🔄 [DropBeat] Ensuring content script for tab:', tabId);
    
    // Track injection attempts
    let attempts = 0;
    const maxAttempts = 3;
    
    while (attempts < maxAttempts) {
        try {
            // Check if tab still exists
            try {
                const tab = await chrome.tabs.get(tabId);
                if (!tab?.url?.includes('music.youtube.com')) {
                    console.log('⚠️ [DropBeat] Tab no longer valid:', tabId);
                    return false;
                }
            } catch (error) {
                console.log('⚠️ [DropBeat] Tab no longer exists:', tabId);
                return false;
            }
            
            // First check health
            const isHealthy = await checkContentScriptHealth(tabId);
            if (isHealthy) {
                console.log('✅ [DropBeat] Content script healthy');
                return true;
            }

            // If not healthy and this isn't our first attempt, wait longer
            if (attempts > 0) {
                await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempts)));
            }

            // If not healthy, try to reinject
            console.log(`🔄 [DropBeat] Reinjecting content script (attempt ${attempts + 1}/${maxAttempts})`);
            await chrome.scripting.executeScript({
                target: { tabId },
                files: ['content.js']
            });
            
            // Wait for script to initialize with increasing delays
            await new Promise(r => setTimeout(r, 1000 + (attempts * 500)));
            
            // Verify health after injection
            const healthAfterInjection = await checkContentScriptHealth(tabId);
            if (healthAfterInjection) {
                console.log('✅ [DropBeat] Script reinjection successful');
                return true;
            }
            
            attempts++;
        } catch (error) {
            console.error('❌ [DropBeat] Error in ensureContentScript:', error);
            attempts++;
            // Wait before retrying
            await new Promise(r => setTimeout(r, 1000));
        }
    }
    
    console.log('❌ [DropBeat] Failed to ensure content script after', maxAttempts, 'attempts');
    return false;
}