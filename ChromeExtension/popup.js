console.log('🎵 [DropBeat] Popup loaded');

document.addEventListener('DOMContentLoaded', function() {
    const statusDiv = document.getElementById('status');
    const connectionStatus = document.getElementById('connection-status');

    function updateStatus(state) {
        console.log('🔄 [DropBeat] Updating status:', state);
        
        if (state.isConnected) {
            statusDiv.textContent = 'Connected to DropBeat';
            statusDiv.className = 'status connected';
            connectionStatus.textContent = 'Connected';
        } else {
            statusDiv.textContent = state.lastError || 'Not connected to DropBeat';
            statusDiv.className = 'status disconnected';
            connectionStatus.textContent = 'Disconnected';
        }
    }

    // Listen for status updates
    chrome.runtime.onMessage.addListener((message) => {
        if (message.type === 'CONNECTION_STATUS') {
            updateStatus(message.status);
        }
    });

    // Get initial status
    chrome.runtime.sendMessage({ type: 'GET_CONNECTION_STATUS' }, (response) => {
        if (response) {
            updateStatus(response);
        }
    });
});