// Sessions list management
import { relativeTime } from './chat.js';

export class SessionsManager {
  constructor(listEl, onSelect) {
    this.listEl = listEl;
    this.onSelect = onSelect;
    this.sessions = [];
    this.activeId = null;
  }

  update(sessions) {
    this.sessions = sessions || [];
    this.render();
  }

  setActive(sessionId) {
    this.activeId = sessionId;
    this.listEl.querySelectorAll('.session-item').forEach(el => {
      el.classList.toggle('active', el.dataset.id === sessionId);
    });
  }

  render() {
    this.listEl.innerHTML = '';
    if (!this.sessions.length) {
      this.listEl.innerHTML = '<div style="padding:24px;text-align:center;color:var(--text-muted);font-size:13px;">No sessions</div>';
      return;
    }

    for (const s of this.sessions) {
      const item = document.createElement('div');
      item.className = 'session-item' + (s.id === this.activeId ? ' active' : '');
      item.dataset.id = s.id;

      const name = s.name || s.id?.substring(0, 8) || 'Session';
      const preview = s.lastMessage || s.preview || '';
      const time = relativeTime(s.updatedAt || s.timestamp);

      item.innerHTML = `
        <div class="session-name">${time ? `<span class="session-time">${time}</span>` : ''}${this._escHtml(name)}</div>
        <div class="session-preview">${this._escHtml(preview)}</div>
      `;

      item.addEventListener('click', () => {
        this.setActive(s.id);
        this.onSelect(s.id);
      });

      this.listEl.appendChild(item);
    }
  }

  _escHtml(s) {
    if (!s) return '';
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
