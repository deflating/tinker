// Connection screen logic
const STORAGE_KEY = 'familiar-mini-server';

export function getSavedServer() {
  return localStorage.getItem(STORAGE_KEY) || '';
}

export function saveServer(host) {
  localStorage.setItem(STORAGE_KEY, host);
}

export function setupConnectionScreen(inputEl, btnEl, errorEl, onConnect, autoBtn) {
  const saved = getSavedServer();
  if (saved) inputEl.value = saved;

  const doConnect = () => {
    const host = inputEl.value.trim();
    if (!host) {
      errorEl.textContent = 'Enter a server address';
      return;
    }
    errorEl.textContent = '';
    btnEl.disabled = true;
    btnEl.textContent = 'Connecting...';
    saveServer(host);
    onConnect(host);
  };

  btnEl.addEventListener('click', doConnect);
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); doConnect(); }
  });

  // Auto-connect button (proxy mode — connect to same host we're served from)
  if (autoBtn) {
    autoBtn.addEventListener('click', () => {
      autoBtn.disabled = true;
      autoBtn.textContent = 'Connecting...';
      errorEl.textContent = '';
      onConnect('__auto__');
    });
  }
}

export function resetConnectButton(btnEl) {
  btnEl.disabled = false;
  btnEl.textContent = 'Connect';
}
