console.log('🎵 [DropBeat] Background script loaded');

class WebSocketManager {
    constructor() {
        this.ws = null;
        this.isConnecting = false;
        this.reconnectTimer = null;
        this.pingInterval = null;
        this.reconnectAttempts = 0;
        this.INITIAL_RECONNECT_DELAY = 1000;
        this.MAX_RECONNECT_DELAY = 30000;
        this.PING_INTERVAL = 5000;
        this.lastPongReceived = Date.now();
        this.PONG_TIMEOUT = 15000; // 15 seconds - match macOS app timeout to prevent false disconnections
        this.MAX_RECONNECT_ATTEMPTS = 0;
        this.appDetected = false;
        this.lastTabRecoveryAttempt = 0;
        this.recentAttempts = [];
        this.diagnosticLog = [];
        this.MAX_LOG_ENTRIES = 100;
        this.portCheckTimer = null;
        this.PORT_CHECK_INTERVAL = 30000; // 30 seconds
        this.pendingReconnectTimeouts = new Set(); // Track all pending reconnect timeouts for cleanup
        
        this.state = {
            isConnected: false,
            lastError: null,
            reconnecting: false,
            nextReconnectTime: null,
            connectionState: 'INITIALIZING',
            waitingForApp: false,
            lastAttemptTime: null
        };
        
        // Bind methods
        this.checkConnection = this.checkConnection.bind(this);
        this.handleConnectionError = this.handleConnectionError.bind(this);
        
        // Start with a single connection attempt
        this.initialConnect();
        
        console.log('🎵 [DropBeat] WebSocket Manager initialized');
    }
    
    async initialConnect() {
        try {
            await this.connect();
        } catch (error) {
            if (error?.code === 1006) {
                console.log('ℹ️ [DropBeat] App not detected, starting port checking');
                this.startPortChecking();
            } else {
                this.scheduleReconnect();
            }
        }
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
            console.log('📤 [DropBeat] Sending ping');
            this.ws.send(JSON.stringify({ type: 'PING' }));
        }
    }
    
    stopPingInterval() {
        if (this.pingInterval) {
            console.log('⏰ [DropBeat] Stopping ping interval');
            clearInterval(this.pingInterval);
            this.pingInterval = null;
        }
    }

    async handleConnectionError(error, wasConnected = false) {
        console.log('❌ [DropBeat] Connection error:', error, 'Was connected:', wasConnected);

        // If this was a disconnect from a previously working connection
        if (wasConnected) {
            this.appDetected = true; // Remember that app was working

            // Limit tab recovery to once every 30 seconds
            const now = Date.now();
            if (!this.lastTabRecoveryAttempt || (now - this.lastTabRecoveryAttempt) > 30000) {
                this.lastTabRecoveryAttempt = now;
                try {
                    const tabs = await chrome.tabs.query({ url: "*://music.youtube.com/*" });
                    console.log('🔍 [DropBeat] Found YouTube Music tabs:', tabs.length);

                    // Only recover the active tab or the first tab found
                    const tabToRecover = tabs.find(tab => tab.active) || tabs[0];
                    if (tabToRecover) {
                        console.log('🔄 [DropBeat] Attempting to recover tab:', tabToRecover.id);
                        await ensureContentScript(tabToRecover.id, true);
                    }
                } catch (error) {
                    console.error('❌ [DropBeat] Error recovering tabs:', error);
                }
            } else {
                console.log('⏳ [DropBeat] Skipping tab recovery, too soon since last attempt');
            }
        }

        this.handleDisconnection(error.message || 'Connection error');
    }

    // REMOVED: Duplicate handleConnectionError method that was overriding the above method

    handleOpen() {
        const wasConnected = this.state.isConnected;
        console.log('🎉 [DropBeat] Handling successful connection. Was connected:', wasConnected);
        
        this.appDetected = true;
        this.reconnectAttempts = 0;
        this.state.isConnected = true;
        this.state.lastError = null;
        this.state.reconnecting = false;
        this.state.nextReconnectTime = null;
        this.state.connectionState = 'CONNECTED';
        this.state.waitingForApp = false;
        this.lastPongReceived = Date.now();
        
        this.startPingInterval();
        this.broadcastState();
        
        if (!wasConnected) {
            this.recoverTabs();
        }
    }

    handleDisconnection(reason) {
        console.log('🔴 [DropBeat] Handling disconnection:', reason);
        
        this.cleanup();
        
        this.state.isConnected = false;
        this.state.lastError = reason;
        this.state.reconnecting = true;
        
        // If it was previously connected (app was detected)
        if (this.appDetected) {
            // Check if the app is still running
            this.checkPortAvailable().then(available => {
                if (available) {
                    // App is still running, try to reconnect
                    console.log('🔄 [DropBeat] App still running, scheduling reconnect');
                    this.state.connectionState = 'RECONNECTING';
                    this.state.waitingForApp = false;
                    this.scheduleReconnect();
                } else {
                    // App has been closed, switch to port checking mode with faster interval
                    console.log('ℹ️ [DropBeat] App appears to be closed, switching to port checking');
                    this.state.connectionState = 'WAITING_FOR_APP';
                    this.state.waitingForApp = true;
                    // Keep appDetected true so we know it was running before
                    this.startPortChecking();
                }
                this.broadcastState();
            });
        } else {
            // App was never detected, start port checking with normal interval
            console.log('ℹ️ [DropBeat] No app detected yet, starting port checking');
            this.state.connectionState = 'WAITING_FOR_APP';
            this.state.waitingForApp = true;
            this.startPortChecking();
            this.broadcastState();
        }
    }

    async cleanup() {
        console.log('[DropBeat] Cleaning up connection...');

        this.stopPingInterval();
        this.stopPortChecking();

        // Clear all pending reconnect timeouts
        for (const timeoutId of this.pendingReconnectTimeouts) {
            clearTimeout(timeoutId);
        }
        this.pendingReconnectTimeouts.clear();

        // Clear diagnostic logs when cleaning up
        this.diagnosticLog = [];
        this.recentAttempts = [];

        if (this.ws) {
            try {
                this.ws.close();
            } catch (error) {
                console.log('⚠️ [DropBeat] Error closing WebSocket:', error);
            }
            this.ws = null;
        }
    }

    async connect() {
        this.logDiagnostic('connect_attempt', {
            reconnectAttempts: this.reconnectAttempts,
            lastAttemptTime: this.state.lastAttemptTime
        });

        if (this.isConnecting || this.ws?.readyState === WebSocket.OPEN) {
            console.log('⏳ [DropBeat] Connection already in progress or established');
            return;
        }

        this.isConnecting = true;
        this.state.connectionState = 'CONNECTING';
        this.state.lastAttemptTime = Date.now();
        this.broadcastState();

        console.log('🔌 [DropBeat] Initiating connection...');

        try {
            // Ensure cleanup is complete before creating new connection
            await this.cleanup();

            // Double-check WebSocket is null after cleanup
            if (this.ws) {
                console.log('⚠️ [DropBeat] WebSocket still exists after cleanup, force clearing');
                this.ws = null;
            }

            return new Promise((resolve, reject) => {
                this.ws = new WebSocket('ws://localhost:8089');

                this.ws.onopen = () => {
                    this.isConnecting = false;
                    this.handleOpen();
                    resolve();
                };

                this.ws.onclose = (event) => {
                    this.isConnecting = false;
                    if (!event.wasClean) {
                        this.handleConnectionError(event);
                    }
                    this.handleDisconnection(`Connection closed (${event.code}): ${event.reason || 'No reason provided'}`);
                    reject(event);
                };

                this.ws.onerror = (event) => {
                    this.isConnecting = false;
                    this.handleConnectionError(event);
                    // Don't reject here, let onclose handle it
                };

                this.ws.onmessage = this.handleMessage.bind(this);
            });
        } catch (error) {
            this.isConnecting = false;
            console.error('❌ [DropBeat] Connection failed:', error);
            throw error;
        }
    }
    
    async recoverTabs() {
        try {
            const tabs = await chrome.tabs.query({ url: "*://music.youtube.com/*" });
            console.log('🔍 [DropBeat] Found YouTube Music tabs to recover:', tabs.length);
            
            for (const tab of tabs) {
                console.log('🔄 [DropBeat] Recovering tab:', tab.id);
                await ensureContentScript(tab.id, true);  // Force reload
            }
        } catch (error) {
            console.error('❌ [DropBeat] Error recovering tabs:', error);
        }
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

    handleMessage(event) {
        try {
            const message = JSON.parse(event.data);
            console.log('📥 [DropBeat] WebSocket message received:', message);

            if (message.type === 'PONG') {
                // Only update pong if we still have an active connection
                if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                    this.lastPongReceived = Date.now();
                    console.log('✅ [DropBeat] Pong received');
                } else {
                    console.log('⚠️ [DropBeat] Received PONG but connection is not open');
                }
            } else if (message.type === 'COMMAND') {
                console.log('🎮 [DropBeat] Command received:', message.command);
                this.forwardCommandToYouTubeMusic(message);
            }
        } catch (error) {
            console.error('❌ [DropBeat] Failed to parse message:', error);
        }
    }

    async forwardCommandToYouTubeMusic(message) {
        this.logDiagnostic('forward_command', {
            command: message.command,
            timestamp: Date.now()
        });
        try {
            // Find all YouTube Music tabs
            const tabs = await chrome.tabs.query({ url: '*://music.youtube.com/*' });
            
            if (tabs.length === 0) {
                console.log('⚠️ [DropBeat] No YouTube Music tab found');
                // If it's a request to open YouTube Music or no tab exists, create one
                if (message.command === 'openYouTubeMusic' || ['play', 'pause', 'next', 'previous'].includes(message.command)) {
                    console.log(' [DropBeat] Opening new YouTube Music tab');
                    const newTab = await chrome.tabs.create({ url: 'https://music.youtube.com', active: true });
                    // Wait for the tab to load and content script to be ready
                    await new Promise(resolve => setTimeout(resolve, 3000));
                    // Ensure content script is loaded in new tab
                    await ensureContentScript(newTab.id);
                    return;
                }
                return;
            }

            // Try to find an active YouTube Music tab first
            let targetTab = tabs.find(tab => tab.active) || tabs[0];
            
            // Use the global ensureContentScript function
            const isScriptReady = await ensureContentScript(targetTab.id);
            if (!isScriptReady) {
                console.log('⚠️ [DropBeat] Content script not ready after injection attempts');
                return;
            }

            // Forward the command with enhanced error handling
            console.log('📤 [DropBeat] Forwarding command to tab:', targetTab.id);
            try {
                const response = await chrome.tabs.sendMessage(targetTab.id, message);
                if (response?.error) {
                    throw new Error(response.error);
                }
                console.log('✅ [DropBeat] Command forwarded successfully');
            } catch (error) {
                console.error('❌ [DropBeat] Error forwarding command:', error);
                // If it's a connection error, try to recover
                if (error.message.includes('Could not establish connection')) {
                    await ensureContentScript(targetTab.id);
                }
            }
        } catch (error) {
            console.error('❌ [DropBeat] Error in command forwarding:', error);
        }
    }

    scheduleReconnect() {
        // If we've tried more than 5 times in the last minute, wait longer
        const now = Date.now();
        this.recentAttempts = this.recentAttempts || [];
        this.recentAttempts = this.recentAttempts.filter(time => (now - time) < 60000);
        this.recentAttempts.push(now);

        if (this.recentAttempts.length > 5) {
            console.log('⚠️ [DropBeat] Too many recent reconnection attempts, waiting longer');
            this.state.reconnecting = true;
            this.state.nextReconnectTime = now + 60000;
            this.broadcastState();

            const timeoutId = setTimeout(() => {
                this.pendingReconnectTimeouts.delete(timeoutId);
                this.recentAttempts = [];
                this.reconnectAttempts = 0;
                this.connect().catch(console.error);
            }, 60000); // Wait a full minute
            this.pendingReconnectTimeouts.add(timeoutId);
            return;
        }

        // Calculate delay with exponential backoff, capped at max delay
        const delay = Math.min(
            this.INITIAL_RECONNECT_DELAY * Math.pow(2, this.reconnectAttempts),
            this.MAX_RECONNECT_DELAY
        );

        this.reconnectAttempts++;
        this.state.reconnecting = true;
        this.state.nextReconnectTime = now + delay;
        this.broadcastState();

        console.log(`🔄 [DropBeat] Scheduling reconnect attempt ${this.reconnectAttempts} in ${delay}ms`);

        const timeoutId = setTimeout(async () => {
            this.pendingReconnectTimeouts.delete(timeoutId);
            try {
                await this.connect();
            } catch (error) {
                console.log('❌ [DropBeat] Reconnection failed:', error);
            }
        }, delay);
        this.pendingReconnectTimeouts.add(timeoutId);
    }

    broadcastState() {
        const stateUpdate = {
            ...this.state,
            stateDescription: this.getStateDescription()
        };
        console.log('📢 [DropBeat] Broadcasting state:', stateUpdate);
        chrome.runtime.sendMessage({
            type: 'CONNECTION_STATUS',
            status: stateUpdate
        }).catch(() => {});
    }

    getState() {
        return this.state;
    }

    getStateDescription() {
        switch (this.state.connectionState) {
            case 'INITIALIZING':
                return 'Starting DropBeat extension...';
            case 'CONNECTING':
                return 'Connecting to DropBeat...';
            case 'CONNECTED':
                return 'Connected to DropBeat';
            case 'WAITING_FOR_APP':
                if (this.appDetected) {
                    return 'DropBeat app was closed, waiting for restart...';
                }
                return 'Waiting for DropBeat app to start...';
            case 'RECONNECTING':
                return 'Reconnecting to DropBeat...';
            case 'ERROR':
                if (this.state.waitingForApp) {
                    return 'DropBeat app not running';
                }
                return this.state.lastError || 'Connection error';
            default:
                return 'Unknown state';
        }
    }

    logDiagnostic(event, details) {
        const entry = {
            timestamp: new Date().toISOString(),
            event,
            details
        };
        console.log('📊 [DropBeat Diagnostic]', entry);
        this.diagnosticLog.unshift(entry);
        if (this.diagnosticLog.length > this.MAX_LOG_ENTRIES) {
            this.diagnosticLog.pop();
        }
    }

    async checkPortAvailable() {
        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 1000);
            
            const response = await fetch(`http://localhost:8089/health`, {
                signal: controller.signal
            }).finally(() => clearTimeout(timeoutId));
            
            return response.ok;
        } catch (error) {
            return false;
        }
    }

    startPortChecking() {
        if (this.portCheckTimer) {
            clearInterval(this.portCheckTimer);
        }
        
        // Initial check
        this.checkPortAvailable().then(available => {
            if (available) {
                console.log('✅ [DropBeat] App detected, attempting connection');
                this.connect();
            } else {
                console.log('ℹ️ [DropBeat] App not running, waiting for it to start');
                this.state.connectionState = 'WAITING_FOR_APP';
                this.state.waitingForApp = true;
                this.broadcastState();
            }
        });

        // Use dynamic interval based on previous app detection
        const checkInterval = this.appDetected ? 5000 : 30000; // 5 seconds if app was previously detected
        console.log(`⏰ [DropBeat] Setting port check interval to ${checkInterval}ms`);

        // Set up periodic checking
        this.portCheckTimer = setInterval(async () => {
            const available = await this.checkPortAvailable();
            if (available) {
                if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
                    console.log('✅ [DropBeat] App detected, attempting connection');
                    this.connect();
                }
            } else {
                if (this.ws) {
                    console.log('⚠️ [DropBeat] App no longer available');
                    this.handleDisconnection('App no longer available');
                }
            }
        }, checkInterval);
    }

    stopPortChecking() {
        if (this.portCheckTimer) {
            clearInterval(this.portCheckTimer);
            this.portCheckTimer = null;
        }
    }
}

// Create instance
const wsManager = new WebSocketManager();

// Enhanced message handling
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📥 [DropBeat] Chrome message received:', message, 'from:', sender?.tab?.id);
    
    try {
        switch (message.type) {
            case 'GET_CONNECTION_STATUS':
                console.log('📤 [DropBeat] Sending connection status:', wsManager.getState());
                sendResponse(wsManager.getState());
                return true; // Keep the message channel open for the async response
            case 'TRACK_INFO':
                if (wsManager.ws?.readyState === WebSocket.OPEN) {
                    try {
                        wsManager.ws.send(JSON.stringify(message));
                        console.log('✅ [DropBeat] Track info forwarded to WebSocket');
                        sendResponse({ sent: true });
                    } catch (error) {
                        console.error('❌ [DropBeat] Error sending track info:', error);
                        sendResponse({ sent: false, error: error.message });
                        // Try to recover WebSocket if needed
                        if (error.message.includes('WebSocket is not open')) {
                            wsManager.handleDisconnection('WebSocket send failed');
                        }
                    }
                } else {
                    console.log('⚠️ [DropBeat] WebSocket not connected, track info not sent');
                    sendResponse({ sent: false, error: 'Not connected' });
                    // Try to reconnect WebSocket
                    wsManager.connect().catch(console.error);
                }
                break;
            case 'PING':
                sendResponse({ pong: true, timestamp: Date.now() });
                break;
            default:
                console.log('⚠️ [DropBeat] Unknown message type:', message.type);
                sendResponse({ error: 'Unknown message type' });
        }
    } catch (error) {
        console.error('❌ [DropBeat] Error handling message:', error);
        sendResponse({ error: error.message });
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

async function ensureContentScript(tabId, forceReload = false) {
    console.log('🔍 [DropBeat] Ensuring content script for tab:', tabId, 'Force reload:', forceReload);
    
    try {
        // If force reload, try to remove existing content script first
        if (forceReload) {
            try {
                await chrome.scripting.unregisterContentScripts();
            } catch (error) {
                console.log('ℹ️ [DropBeat] No existing scripts to unregister:', error);
            }
        }
        
        // Check if content script is responsive
        let isHealthy = false;
        if (!forceReload) {
            try {
                const response = await chrome.tabs.sendMessage(tabId, { type: 'HEALTH_CHECK', timestamp: Date.now() });
                isHealthy = response?.healthy === true;
                console.log('🏥 [DropBeat] Content script health check:', isHealthy ? 'healthy' : 'unhealthy');
            } catch (error) {
                console.log('⚠️ [DropBeat] Health check failed:', error);
            }
        }
        
        if (!isHealthy || forceReload) {
            console.log('🔄 [DropBeat] Injecting content script...');
            await chrome.scripting.executeScript({
                target: { tabId },
                files: ['content.js']
            });
            
            // Wait for script to initialize
            let attempts = 0;
            while (attempts < 5) {
                try {
                    const response = await chrome.tabs.sendMessage(tabId, { type: 'HEALTH_CHECK', timestamp: Date.now() });
                    if (response?.healthy === true) {
                        console.log('✅ [DropBeat] Content script ready');
                return true;
                    }
                } catch (error) {
                    console.log('⏳ [DropBeat] Waiting for content script... attempt:', attempts + 1);
                }
                attempts++;
                await new Promise(r => setTimeout(r, 1000));
            }
            
            console.log('❌ [DropBeat] Content script failed to initialize');
            return false;
        }
        
        return true;
    } catch (error) {
        console.error('❌ [DropBeat] Error ensuring content script:', error);
        return false;
    }
}