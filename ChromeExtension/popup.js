console.log('🎵 [DropBeat] Popup loaded');

document.addEventListener('DOMContentLoaded', function() {
    function updateConnectionStatus(status) {
        const statusElement = document.getElementById('connection-status');
        const statusIcon = document.getElementById('status-icon');
        const appStatus = document.getElementById('app-status');
        const appStatusMessage = document.getElementById('app-status-message');
        
        if (!statusElement || !statusIcon) return;
        
        console.log('🔄 [DropBeat] Updating popup status:', status);
        
        statusElement.textContent = status.stateDescription || 'Unknown';
        
        // Update status icon and class based on connection state
        switch (status.connectionState) {
            case 'CONNECTED':
                statusIcon.textContent = '🟢';
                statusElement.className = 'status-text connected';
                appStatus.className = 'app-status running';
                appStatusMessage.textContent = 'DropBeat is running';
                break;
            case 'CONNECTING':
            case 'RECONNECTING':
                statusIcon.textContent = '🟡';
                statusElement.className = 'status-text connecting';
                appStatus.className = 'app-status';
                break;
            case 'WAITING_FOR_APP':
                statusIcon.textContent = '⏳';
                statusElement.className = 'status-text waiting';
                appStatus.className = 'app-status not-running';
                appStatusMessage.textContent = 'DropBeat app is not running';
                break;
            case 'ERROR':
                statusIcon.textContent = '🔴';
                statusElement.className = 'status-text error';
                if (!status.waitingForApp) {
                    appStatus.className = 'app-status not-running';
                    appStatusMessage.textContent = 'Connection error - Please restart DropBeat';
                }
                break;
            default:
                statusIcon.textContent = '⚪';
                statusElement.className = 'status-text';
                appStatus.className = 'app-status';
        }
        
        // Show additional info if waiting for app
        const infoElement = document.getElementById('additional-info');
        if (infoElement) {
            if (status.waitingForApp) {
                infoElement.textContent = 'Please make sure the DropBeat app is running';
                infoElement.style.display = 'block';
            } else {
                infoElement.style.display = 'none';
            }
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