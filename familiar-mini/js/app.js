// Main app logic
import { WebSocketManager } from './websocket.js';
import { ChatRenderer } from './chat.js';
import { SessionsManager } from './sessions.js';
import { setupConnectionScreen, resetConnectButton } from './connection.js';
import { setupAttachments } from './attachments.js';

// --- DOM refs ---
const screenConnect = document.getElementById('screen-connect');
const screenApp = document.getElementById('screen-app');
const serverInput = document.getElementById('server-input');
const connectBtn = document.getElementById('connect-btn');
const connectError = document.getElementById('connect-error');
const sidebarToggle = document.getElementById('sidebar-toggle');
const sidebar = document.getElementById('sidebar');
const sidebarOverlay = document.getElementById('sidebar-overlay');
const sessionsList = document.getElementById('sessions-list');
const messagesContainer = document.getElementById('messages-container');
const loadingIndicator = document.getElementById('loading-indicator');
const messageInput = document.getElementById('message-input');
const sendBtn = document.getElementById('send-btn');
const attachBtn = document.getElementById('attach-btn');
const fileInput = document.getElementById('file-input');
const connectionDot = document.getElementById('connection-dot');
const disconnectBtn = document.getElementById('disconnect-btn');
const headerSessionName = document.getElementById('header-session-name');
const autoConnectBtn = document.getElementById('auto-connect-btn');

// --- State ---
const ws = new WebSocketManager();
const chat = new ChatRenderer(messagesContainer, loadingIndicator);
const sessions = new SessionsManager(sessionsList, (id) => {
  ws.switchSession(id);
  closeSidebar();
});

let currentSessionId = null;

// --- Cat blinking ---
function startCatBlink() {
  const catEyeSets = [
    document.getElementById('connect-cat-eyes'),
    document.getElementById('header-cat-eyes'),
  ];

  function blink() {
    catEyeSets.forEach(set => {
      if (!set) return;
      const eyes = set.querySelectorAll('.cat-eye, .cat-eye-mini');
      eyes.forEach(e => { e.className = e.className.replace(/open|half|closed/, 'half'); });
      setTimeout(() => {
        eyes.forEach(e => { e.className = e.className.replace(/open|half|closed/, 'closed'); });
      }, 80);
      setTimeout(() => {
        eyes.forEach(e => { e.className = e.className.replace(/open|half|closed/, 'half'); });
      }, 160);
      setTimeout(() => {
        eyes.forEach(e => { e.className = e.className.replace(/open|half|closed/, 'open'); });
      }, 240);
    });
  }

  setInterval(() => {
    blink();
    // Occasional double blink
    if (Math.random() < 0.3) {
      setTimeout(blink, 500);
    }
  }, 3000 + Math.random() * 2000);
}
startCatBlink();

// --- Screens ---
function showApp() {
  screenConnect.classList.remove('active');
  screenApp.classList.add('active');
}

function showConnect() {
  screenApp.classList.remove('active');
  screenConnect.classList.add('active');
  resetConnectButton(connectBtn);
}

// --- Sidebar ---
function openSidebar() {
  sidebar.classList.add('open');
  sidebarOverlay.classList.add('visible');
}

function closeSidebar() {
  sidebar.classList.remove('open');
  sidebarOverlay.classList.remove('visible');
}

sidebarToggle.addEventListener('click', () => {
  sidebar.classList.contains('open') ? closeSidebar() : openSidebar();
});
sidebarOverlay.addEventListener('click', closeSidebar);

// --- Connection screen ---
setupConnectionScreen(serverInput, connectBtn, connectError, (host) => {
  ws.connect(host);
}, autoConnectBtn);

// --- Disconnect ---
disconnectBtn.addEventListener('click', () => {
  ws.disconnect();
  chat.clear();
  sessions.update([]);
  currentSessionId = null;
  showConnect();
});

// --- WebSocket events ---
ws.on('connected', () => {
  connectionDot.className = 'connection-dot connected';
  showApp();
  resetConnectButton(connectBtn);
});

ws.on('disconnected', () => {
  connectionDot.className = 'connection-dot disconnected';
});

ws.on('reconnecting', () => {
  connectionDot.className = 'connection-dot disconnected';
});

ws.on('error', (err) => {
  connectError.textContent = err || 'Connection error';
  resetConnectButton(connectBtn);
});

ws.on('sync', (data) => {
  // Full state sync
  if (data.sessions) {
    sessions.update(data.sessions);
  }
  if (data.session) {
    currentSessionId = data.session.id;
    sessions.setActive(currentSessionId);
    headerSessionName.textContent = data.session.name || 'Session';
  }
  if (data.messages) {
    chat.clear();
    chat.renderMessages(data.messages);
  }
  if (data.state) {
    chat.setLoading(data.state.isLoading || data.state.runState === 'running');
  }
});

ws.on('message', (data) => {
  if (data.message) {
    chat.renderMessage(data.message);
  }
});

ws.on('state', (data) => {
  chat.setLoading(data.isLoading || data.runState === 'running');
});

// --- Input ---
function autoResizeInput() {
  messageInput.style.height = 'auto';
  messageInput.style.height = Math.min(messageInput.scrollHeight, 120) + 'px';
}

messageInput.addEventListener('input', autoResizeInput);

messageInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
});

sendBtn.addEventListener('click', sendMessage);

function sendMessage() {
  const text = messageInput.value.trim();
  if (!text) return;
  ws.sendMessage(text);
  messageInput.value = '';
  autoResizeInput();
}

// --- Attachments ---
setupAttachments(attachBtn, fileInput, (filename, base64) => {
  const caption = messageInput.value.trim();
  ws.sendAttachment(filename, base64, caption);
  messageInput.value = '';
  autoResizeInput();
});

// --- Service Worker ---
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
