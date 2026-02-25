// Chat UI rendering
const TOOL_ICONS = {
  Read: '<svg viewBox="0 0 16 16"><path d="M2 2h8l4 4v8H2z"/><path d="M10 2v4h4"/></svg>',
  Write: '<svg viewBox="0 0 16 16"><path d="M2 14l1-4L11 2l3 3L6 13z"/></svg>',
  Edit: '<svg viewBox="0 0 16 16"><path d="M11 1l4 4-9 9H2v-4z"/></svg>',
  Bash: '<svg viewBox="0 0 16 16"><path d="M2 3h12v10H2z"/><path d="M5 7l2 2-2 2"/></svg>',
  Glob: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><path d="M5 8l2 2 4-4"/></svg>',
  Grep: '<svg viewBox="0 0 16 16"><circle cx="7" cy="7" r="4"/><path d="M10 10l4 4"/></svg>',
  WebFetch: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c-2 2-2 10 0 12M8 2c2 2 2 10 0 12"/></svg>',
  WebSearch: '<svg viewBox="0 0 16 16"><circle cx="7" cy="7" r="4"/><path d="M10 10l4 4"/></svg>',
  default: '<svg viewBox="0 0 16 16"><path d="M8 2l6 4v4l-6 4-6-4V6z"/></svg>',
};

function getToolIcon(name) {
  return TOOL_ICONS[name] || TOOL_ICONS.default;
}

function toolSummary(msg) {
  const name = msg.toolName || 'Tool';
  let summary = '';
  if (msg.content && typeof msg.content === 'string') {
    // Try to extract a path or brief info
    const content = msg.content;
    if (content.length < 80) {
      summary = content;
    } else {
      // Try to find a file path
      const pathMatch = content.match(/[\/~][\w\-\/.]+/);
      if (pathMatch) {
        summary = pathMatch[0];
      } else {
        summary = content.substring(0, 60) + '...';
      }
    }
  }
  return { name, summary };
}

function renderMarkdown(text) {
  if (!text) return '';
  try {
    marked.setOptions({
      highlight: (code, lang) => {
        if (lang && hljs.getLanguage(lang)) {
          return hljs.highlight(code, { language: lang }).value;
        }
        return hljs.highlightAuto(code).value;
      },
      breaks: true,
      gfm: true,
    });
    return marked.parse(text);
  } catch {
    return escapeHtml(text);
  }
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function relativeTime(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const now = Date.now();
  const diff = (now - d.getTime()) / 1000;
  if (diff < 60) return 'now';
  if (diff < 3600) return Math.floor(diff / 60) + 'm';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h';
  return Math.floor(diff / 86400) + 'd';
}

export class ChatRenderer {
  constructor(container, loadingIndicator) {
    this.container = container;
    this.loadingIndicator = loadingIndicator;
    this.renderedIds = new Set();
    this.elements = new Map();
    this.isNearBottom = true;
    container.addEventListener('scroll', () => {
      const threshold = 80;
      this.isNearBottom = container.scrollHeight - container.scrollTop - container.clientHeight < threshold;
    });
  }

  clear() {
    this.container.innerHTML = '';
    this.renderedIds.clear();
    this.elements.clear();
  }

  scrollToBottom(force = false) {
    if (force || this.isNearBottom) {
      requestAnimationFrame(() => {
        this.container.scrollTop = this.container.scrollHeight;
      });
    }
  }

  setLoading(loading) {
    this.loadingIndicator.classList.toggle('hidden', !loading);
    if (loading) this.scrollToBottom();
  }

  renderMessages(messages) {
    if (!messages || !messages.length) return;
    for (const msg of messages) {
      this.renderMessage(msg);
    }
    this.scrollToBottom();
  }

  renderMessage(msg) {
    if (!msg || !msg.id) return;

    // Update existing element if present
    if (this.renderedIds.has(msg.id)) {
      this._updateMessage(msg);
      return;
    }

    this.renderedIds.add(msg.id);
    const el = this._createElement(msg);
    if (el) {
      this.elements.set(msg.id, el);
      this.container.appendChild(el);
      this.scrollToBottom();
    }
  }

  _createElement(msg) {
    const type = msg.messageType || msg.role;

    if (type === 'toolUse') return this._createToolRow(msg);
    if (type === 'toolResult' || type === 'toolError') return null; // hidden by default
    if (type === 'thinking') return this._createThinkingRow(msg);

    // Regular text message
    const row = document.createElement('div');
    row.className = `message-row ${msg.role || 'assistant'}`;
    row.dataset.id = msg.id;

    const bubble = document.createElement('div');
    bubble.className = 'message-bubble';

    if (msg.role === 'user') {
      bubble.textContent = msg.content || '';
    } else if (msg.role === 'system') {
      bubble.textContent = msg.content || '';
    } else {
      bubble.innerHTML = renderMarkdown(msg.content || '');
    }

    row.appendChild(bubble);
    return row;
  }

  _createToolRow(msg) {
    const { name, summary } = toolSummary(msg);
    const row = document.createElement('div');
    row.className = 'tool-row';
    row.dataset.id = msg.id;

    row.innerHTML = `
      <div class="tool-icon">${getToolIcon(name)}</div>
      <span class="tool-name">${escapeHtml(name)}</span>
      <span class="tool-summary">${escapeHtml(summary)}</span>
      ${msg.isComplete === false ? '<div class="tool-spinner"></div>' : ''}
    `;
    return row;
  }

  _createThinkingRow(msg) {
    const row = document.createElement('div');
    row.className = 'thinking-row';
    row.dataset.id = msg.id;

    const toggle = document.createElement('button');
    toggle.className = 'thinking-toggle';
    toggle.innerHTML = '<span class="arrow">&#9654;</span> Thinking...';

    const content = document.createElement('div');
    content.className = 'thinking-content';
    content.textContent = msg.content || '';

    toggle.addEventListener('click', () => {
      toggle.classList.toggle('open');
      content.classList.toggle('open');
    });

    row.appendChild(toggle);
    row.appendChild(content);
    return row;
  }

  _updateMessage(msg) {
    const el = this.elements.get(msg.id);
    if (!el) return;

    const type = msg.messageType || msg.role;

    if (type === 'toolUse') {
      const { name, summary } = toolSummary(msg);
      const summaryEl = el.querySelector('.tool-summary');
      if (summaryEl) summaryEl.textContent = summary;
      // Remove spinner if complete
      if (msg.isComplete !== false) {
        const spinner = el.querySelector('.tool-spinner');
        if (spinner) spinner.remove();
      }
      return;
    }

    if (type === 'thinking') {
      const content = el.querySelector('.thinking-content');
      if (content) content.textContent = msg.content || '';
      return;
    }

    // Text message update
    const bubble = el.querySelector('.message-bubble');
    if (!bubble) return;
    if (msg.role === 'user') {
      bubble.textContent = msg.content || '';
    } else {
      bubble.innerHTML = renderMarkdown(msg.content || '');
    }
    this.scrollToBottom();
  }
}

export { relativeTime };
