// WebSocket connection manager
export class WebSocketManager {
  constructor() {
    this.ws = null;
    this.url = '';
    this.connected = false;
    this.reconnectTimer = null;
    this.pingTimer = null;
    this.listeners = {};
    this.autoReconnect = true;
  }

  on(event, fn) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(fn);
  }

  emit(event, data) {
    (this.listeners[event] || []).forEach(fn => fn(data));
  }

  connect(host) {
    this.autoReconnect = true;
    if (host === '__auto__') {
      // Connect to same host/port we were served from (proxy mode)
      const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      this.url = `${proto}//${location.host}`;
    } else {
      this.url = host.startsWith('ws://') || host.startsWith('wss://') ? host : `ws://${host}`;
    }
    this._doConnect();
  }

  _doConnect() {
    this.close(false);
    try {
      this.ws = new WebSocket(this.url);
    } catch (e) {
      this.emit('error', 'Invalid server address');
      return;
    }

    this.ws.onopen = () => {
      this.connected = true;
      this.emit('connected');
      // Send auth immediately
      this.send({ type: 'auth', token: '' });
      // Start ping interval
      this._startPing();
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        this.emit('message', msg);
        this.emit(msg.type, msg);
      } catch (e) {
        // ignore non-JSON
      }
    };

    this.ws.onerror = () => {
      this.emit('error', 'Connection failed');
    };

    this.ws.onclose = () => {
      const wasConnected = this.connected;
      this.connected = false;
      this._stopPing();
      this.emit('disconnected');
      if (this.autoReconnect && wasConnected) {
        this._scheduleReconnect();
      } else if (this.autoReconnect) {
        this._scheduleReconnect();
      }
    };
  }

  _startPing() {
    this._stopPing();
    this.pingTimer = setInterval(() => {
      if (this.connected) this.send({ type: 'ping' });
    }, 30000);
  }

  _stopPing() {
    if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null; }
  }

  _scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.connected && this.autoReconnect) {
        this.emit('reconnecting');
        this._doConnect();
      }
    }, 10000);
  }

  send(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  sendMessage(text) {
    this.send({ type: 'send', text });
  }

  switchSession(sessionId) {
    this.send({ type: 'switch_session', sessionId });
  }

  sendAttachment(filename, base64Data, text) {
    this.send({ type: 'send_attachment', filename, data: base64Data, text: text || '' });
  }

  close(permanent = true) {
    if (permanent) this.autoReconnect = false;
    if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
    this._stopPing();
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.onerror = null;
      this.ws.close();
      this.ws = null;
    }
    this.connected = false;
  }

  disconnect() {
    this.close(true);
    this.emit('disconnected');
  }
}
