console.log('🎵 [DropBeat] Popup loaded');

document.addEventListener('DOMContentLoaded', function() {
    function updateConnectionStatus(status) {
        const appStatus = document.getElementById('app-status');
        const appStatusMessage = document.getElementById('app-status-message');
        const actionHint = document.querySelector('.action-hint');
        
        if (!appStatus || !appStatusMessage || !actionHint) return;
        
        console.log('🔄 [DropBeat] Updating popup status:', status);
        
        // Update status based on connection state
        switch (status.connectionState) {
            case 'CONNECTED':
                appStatus.className = 'app-status';
                appStatusMessage.textContent = 'App and Extension connected';
                actionHint.textContent = 'Ready to control your music playback';
                break;
            case 'CONNECTING':
            case 'RECONNECTING':
                appStatus.className = 'app-status not-running';
                appStatusMessage.textContent = 'Establishing connection';
                actionHint.textContent = 'Please check if DropBeats app is running';
                break;
            case 'WAITING_FOR_APP':
                appStatus.className = 'app-status not-running';
                appStatusMessage.textContent = 'Connection lost';
                actionHint.textContent = 'Please check if DropBeats app is running';
                break;
            case 'ERROR':
                appStatus.className = 'app-status not-running';
                appStatusMessage.textContent = 'Connection error';
                actionHint.textContent = 'Please check if DropBeats app is running';
                break;
            default:
                appStatus.className = 'app-status not-running';
                appStatusMessage.textContent = 'Initializing';
                actionHint.textContent = 'Please check if DropBeats app is running';
        }
    }

    // Listen for connection status updates
    chrome.runtime.onMessage.addListener((message) => {
        if (message.type === 'CONNECTION_STATUS') {
            console.log('📥 [DropBeat] Received status update:', message.status);
            updateConnectionStatus(message.status);
        }
    });

    // Get initial connection status
    console.log('🔍 [DropBeat] Requesting initial connection status');
    chrome.runtime.sendMessage({ type: 'GET_CONNECTION_STATUS' }, (response) => {
        if (response) {
            console.log('✅ [DropBeat] Got initial status:', response);
            updateConnectionStatus(response);
        } else {
            console.log('⚠️ [DropBeat] No initial status received');
            // Show initializing state
            updateConnectionStatus({
                connectionState: 'INITIALIZING',
                stateDescription: 'Initializing...',
                waitingForApp: false
            });
        }
    });
});