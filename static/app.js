// ── Tab switching ──────────────────────────────────────────────────────────────

const TAB_IDS = ['downloads', 'subscriptions', 'playlists', 'config'];
// Mapeamento de IDs de tab para nomes dos botões na sidebar
const TAB_BTN_IDS = ['downloads', 'subscriptions', 'playlists', 'config'];

function showTab(name) {
  TAB_IDS.forEach(t => {
    document.getElementById(`tab-${t}`).hidden = (t !== name);
    const btn = document.getElementById(`tab-btn-${t}`);
    if (btn) btn.classList.toggle('active', t === name);
  });
  if (name === 'config') loadConfig();
  if (name === 'subscriptions') checkAuthStatus();
  if (name === 'playlists') syncPlaylistAuthStatus();
}

// ── Toast notifications ────────────────────────────────────────────────────────

function showToast(message, type = 'info', duration = 4000) {
  const container = document.getElementById('toast-container');
  const icons = { success: 'check-circle', error: 'x-circle', info: 'info' };
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `<i data-lucide="${icons[type]}" class="w-4 h-4 flex-shrink-0"></i><span>${escHtml(message)}</span>`;
  container.appendChild(toast);
  lucide.createIcons({ nodes: [toast] });
  setTimeout(() => {
    toast.style.animation = 'toastOut 0.2s ease forwards';
    setTimeout(() => toast.remove(), 200);
  }, duration);
}

// ── Clipboard auto-paste ───────────────────────────────────────────────────────

// ── SSE helpers ────────────────────────────────────────────────────────────────

async function streamPost(url, body, onEvent) {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ message: resp.statusText }));
    onEvent({ status: 'error', message: err.message || resp.statusText });
    return;
  }
  await readSSEStream(resp, onEvent);
}

async function streamFormPost(url, formData, onEvent) {
  const resp = await fetch(url, { method: 'POST', body: formData });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ message: resp.statusText }));
    onEvent({ status: 'error', message: err.message || resp.statusText });
    return;
  }
  await readSSEStream(resp, onEvent);
}

async function readSSEStream(resp, onEvent) {
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split('\n\n');
    buffer = parts.pop();
    for (const part of parts) {
      const line = part.replace(/^data: /, '').trim();
      if (line) {
        try { onEvent(JSON.parse(line)); } catch (_) {}
      }
    }
  }
}

// ── Log toggle ─────────────────────────────────────────────────────────────────

function toggleLog(logId) {
  const log = document.getElementById(logId);
  // derive label id: "download-log" → "download-log-toggle-label"
  const labelId = logId + '-toggle-label';
  const label = document.getElementById(labelId);
  const hidden = log.classList.toggle('hidden');
  if (label) label.textContent = hidden ? 'Ver log' : 'Ocultar log';
}

// ── Downloads ─────────────────────────────────────────────────────────────────

const downloadForm = document.getElementById('download-form');
const downloadBtn = document.getElementById('download-btn');
let selectedFormatId = null;
let currentDownloadId = null;

function toggleSubLangs() {
  const checked = document.getElementById('subtitles').checked;
  document.getElementById('sub-langs-row').classList.toggle('hidden', !checked);
}

function toggleTrim() {
  const checked = document.getElementById('trim-toggle').checked;
  document.getElementById('trim-row').classList.toggle('hidden', !checked);
}

// ── Drag & drop URL ────────────────────────────────────────────────────────────

const dropZone = document.getElementById('drop-zone');
['dragenter', 'dragover'].forEach(ev => {
  dropZone.addEventListener(ev, e => { e.preventDefault(); dropZone.classList.add('drag-over'); });
});
['dragleave', 'drop'].forEach(ev => {
  dropZone.addEventListener(ev, () => dropZone.classList.remove('drag-over'));
});
dropZone.addEventListener('drop', e => {
  e.preventDefault();
  const text = e.dataTransfer.getData('text/plain') || e.dataTransfer.getData('text/uri-list');
  if (text && (text.includes('youtube.com') || text.includes('youtu.be') || text.includes('instagram.com'))) {
    document.getElementById('url-input').value = text.trim();
    highlightPlatformIcon(text);
    inspectFormats();
  }
});

// Auto-paste from clipboard on URL field focus
document.getElementById('url-input').addEventListener('focus', async () => {
  try {
    const text = await navigator.clipboard.readText();
    const field = document.getElementById('url-input');
    if (!field.value && (text.includes('youtube.com') || text.includes('youtu.be') || text.includes('instagram.com'))) {
      field.value = text.trim();
      highlightPlatformIcon(text);
      // Auto-inspecionar
      inspectFormats();
    }
  } catch (_) {}
});

document.getElementById('url-input').addEventListener('input', (e) => {
  highlightPlatformIcon(e.target.value);
});

// Auto-inspecionar ao colar (Ctrl+V / Cmd+V)
document.getElementById('url-input').addEventListener('paste', (e) => {
  setTimeout(() => {
    const val = document.getElementById('url-input').value.trim();
    if (val && (val.includes('youtube.com') || val.includes('youtu.be') || val.includes('instagram.com'))) {
      highlightPlatformIcon(val);
      inspectFormats();
    }
  }, 50);
});

function highlightPlatformIcon(url) {
  const yt = document.getElementById('icon-yt');
  const ig = document.getElementById('icon-ig');
  const isYT = url.includes('youtube.com') || url.includes('youtu.be');
  const isIG = url.includes('instagram.com');
  yt.classList.toggle('active', isYT);
  ig.classList.toggle('active', isIG);
}

function clearUrlAndPreview() {
  document.getElementById('url-input').value = '';
  document.getElementById('video-preview').classList.add('hidden');
  document.getElementById('formats-section').classList.add('hidden');
  document.getElementById('player-section').classList.add('hidden');
  document.getElementById('icon-yt').classList.remove('active');
  document.getElementById('icon-ig').classList.remove('active');
  selectedFormatId = null;
  if (ytPlayer) { ytPlayer.destroy(); ytPlayer = null; }
}

// ── Download queue ─────────────────────────────────────────────────────────────

let downloadQueue = [];
let queueRunning = false;

function getFormData() {
  const previewThumb = document.getElementById('preview-thumb');
  const thumbUrl = previewThumb && previewThumb.src && !previewThumb.src.endsWith('/') ? previewThumb.src : '';
  return {
    url: document.getElementById('url-input').value.trim(),
    format_id: selectedFormatId || null,
    quality: document.getElementById('quality-select').value,
    format: document.getElementById('format-select').value,
    audio_only: document.getElementById('audio-only').checked,
    subtitles: document.getElementById('subtitles').checked,
    sub_langs: document.getElementById('sub-langs-input').value || 'en,pt',
    category: document.getElementById('category-select').value,
    filename: document.getElementById('filename-input').value.trim(),
    thumbnail: thumbUrl,
    trim_start: document.getElementById('trim-toggle').checked ? document.getElementById('trim-start').value.trim() || null : null,
    trim_end: document.getElementById('trim-toggle').checked ? document.getElementById('trim-end').value.trim() || null : null,
  };
}

function addToQueue() {
  const data = getFormData();
  if (!data.url) { showToast('Cole uma URL primeiro', 'info'); return; }
  downloadQueue.push({ ...data, status: 'pending', id: crypto.randomUUID() });
  document.getElementById('url-input').value = '';
  selectedFormatId = null;
  renderQueue();
  showToast('Adicionado à fila', 'info', 2000);
}

function renderQueue() {
  const section = document.getElementById('queue-section');
  const list = document.getElementById('queue-list');
  if (!downloadQueue.length) { section.classList.add('hidden'); return; }
  section.classList.remove('hidden');
  list.innerHTML = '';
  downloadQueue.forEach((item, i) => {
    const statusClass = `queue-status-${item.status}`;
    const statusLabel = { pending: 'Pendente', active: 'Baixando', done: 'Concluído', error: 'Erro' }[item.status] || item.status;
    const li = document.createElement('li');
    li.className = 'queue-item';
    li.innerHTML = `
      <span class="flex-1 truncate text-gray-300">${escHtml(item.url)}</span>
      <span class="queue-status ${statusClass}">${statusLabel}</span>
      ${item.status === 'pending' ? `<button onclick="removeFromQueue(${i})" class="text-gray-600 hover:text-red-400 transition-colors"><i data-lucide="x" class="w-3.5 h-3.5"></i></button>` : ''}
    `;
    list.appendChild(li);
  });
  lucide.createIcons({ nodes: [list] });
}

function removeFromQueue(index) {
  downloadQueue.splice(index, 1);
  renderQueue();
}

async function startQueue() {
  if (queueRunning) return;
  queueRunning = true;
  document.getElementById('start-queue-btn').disabled = true;

  for (const item of downloadQueue) {
    if (item.status !== 'pending') continue;
    item.status = 'active';
    renderQueue();
    await runSingleDownload(item);
    renderQueue();
  }

  queueRunning = false;
  document.getElementById('start-queue-btn').disabled = false;
  downloadQueue = downloadQueue.filter(i => i.status !== 'done');
  renderQueue();
  if (!downloadQueue.length) showToast('Fila concluída!', 'success');
}

// ── Single download ────────────────────────────────────────────────────────────

function runSingleDownload(item) {
  return new Promise(async (resolve) => {
    const downloadId = item.id || crypto.randomUUID();
    currentDownloadId = downloadId;
    setDownloadUI('active');
    document.getElementById('cancel-download-btn').classList.remove('hidden');

    await streamPost('/api/download', {
      ...item,
      download_id: downloadId,
    }, (ev) => {
      handleDownloadEvent(ev);
      if (ev.status === 'done') { item.status = 'done'; }
      if (ev.status === 'error') { item.status = 'error'; }
    });

    currentDownloadId = null;
    document.getElementById('cancel-download-btn').classList.add('hidden');
    setDownloadUI('idle');
    resolve();
  });
}

async function inspectFormats() {
  const url = document.getElementById('url-input').value.trim();
  if (!url) return;

  const btn = document.getElementById('inspect-btn');
  btn.innerHTML = '<i data-lucide="loader-2" class="w-3.5 h-3.5 animate-spin"></i> Loading...';
  btn.disabled = true;
  selectedFormatId = null;

  try {
    const resp = await fetch(`/api/formats?url=${encodeURIComponent(url)}`);
    const data = await resp.json();
    renderFormats(data.formats || []);
    renderVideoPreview(data);
    loadYouTubePlayer(url, data.duration);
  } catch (e) {
    showToast('Não foi possível buscar os formatos: ' + e.message, 'error');
  } finally {
    btn.innerHTML = '<i data-lucide="scan-search" class="w-4 h-4"></i> Inspecionar';
    btn.disabled = false;
    lucide.createIcons({ nodes: [btn] });
  }
}

// ── YouTube embedded player for trim ───────────────────────────────────────────

let ytPlayer = null;
let ytPlayerReady = false;

// Called by YouTube IFrame API when ready
function onYouTubeIframeAPIReady() {
  // API loaded, player will be created on demand
}

function extractVideoId(url) {
  const m = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

function loadYouTubePlayer(url, duration) {
  const videoId = extractVideoId(url);
  const section = document.getElementById('player-section');

  if (!videoId) {
    section.classList.add('hidden');
    return;
  }

  section.classList.remove('hidden');

  // Destroy old player
  if (ytPlayer) {
    ytPlayer.destroy();
    ytPlayer = null;
  }

  ytPlayerReady = false;
  ytPlayer = new YT.Player('yt-player', {
    videoId: videoId,
    playerVars: {
      autoplay: 0,
      modestbranding: 1,
      rel: 0,
    },
    events: {
      onReady: () => { ytPlayerReady = true; },
    },
  });
}

function renderVideoPreview(data) {
  const preview = document.getElementById('video-preview');
  const thumb = document.getElementById('preview-thumb');
  const title = document.getElementById('preview-title');
  const meta = document.getElementById('preview-meta');

  if (data.title) {
    title.textContent = data.title;
    const parts = [];
    if (data.duration) parts.push(formatDuration(data.duration));
    if (data.uploader) parts.push(data.uploader);
    meta.textContent = parts.join(' · ');

    if (data.thumbnail) {
      thumb.src = `/api/thumbnail?url=${encodeURIComponent(data.thumbnail)}`;
      thumb.onerror = () => { thumb.style.display = 'none'; };
    }
    preview.classList.remove('hidden');
  } else {
    preview.classList.add('hidden');
  }
}

function formatDuration(seconds) {
  if (!seconds) return '';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  return `${m}:${String(s).padStart(2,'0')}`;
}

function renderFormats(formats) {
  const section = document.getElementById('formats-section');
  const list = document.getElementById('formats-list');
  list.innerHTML = '';

  if (!formats.length) { section.classList.add('hidden'); return; }

  const kindLabel = { 'video+audio': '🎬', video: '📹', audio: '🎵' };
  formats.forEach(f => {
    const row = document.createElement('label');
    row.className = 'format-row';
    row.innerHTML = `
      <input type="radio" name="format-pick" value="${f.id}" class="accent-red-500 flex-shrink-0">
      <span class="flex-1 truncate">${kindLabel[f.kind] || ''} ${escHtml(f.label)}</span>
      <span class="text-xs text-gray-600 flex-shrink-0">${f.kind}</span>`;
    row.querySelector('input').addEventListener('change', () => { selectedFormatId = f.id; });
    list.appendChild(row);
  });
  section.classList.remove('hidden');
}

downloadForm.addEventListener('submit', async e => {
  e.preventDefault();

  if ('Notification' in window && Notification.permission === 'default') {
    await Notification.requestPermission();
  }

  const data = getFormData();
  if (!data.url) return;

  const item = { ...data, status: 'active', id: crypto.randomUUID() };
  await runSingleDownload(item);
});

async function cancelCurrentDownload() {
  if (!currentDownloadId) return;
  try {
    await fetch('/api/download/cancel', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ download_id: currentDownloadId }),
    });
    showToast('Download cancelado', 'info');
  } catch (_) {}
}

function handleDownloadEvent(ev) {
  const log = document.getElementById('download-log');
  const bar = document.getElementById('download-progress-bar');
  const pct = document.getElementById('download-percent-text');
  const statusText = document.getElementById('download-status-text');
  const speedRow = document.getElementById('download-speed-row');

  if (ev.status === 'progress') {
    const p = parseFloat(ev.percent);
    bar.style.width = p + '%';
    pct.textContent = p.toFixed(1) + '%';
    statusText.textContent = 'Baixando...';
    if (ev.speed || ev.eta || ev.total) {
      speedRow.classList.remove('hidden');
      document.getElementById('download-speed').textContent = ev.speed || '';
      document.getElementById('download-eta').textContent = ev.eta ? `ETA ${ev.eta}` : '';
      document.getElementById('download-total-size').textContent = ev.total || '';
    }
  } else if (ev.status === 'log') {
    appendLog(log, ev.message);
  } else if (ev.status === 'done') {
    bar.style.width = '100%';
    pct.textContent = '100%';
    statusText.textContent = 'Concluído!';
    speedRow.classList.add('hidden');
    addHistoryEntry(document.getElementById('url-input').value, ev.output_dir);
    showToast('Download concluído!', 'success');
    if (Notification.permission === 'granted') {
      try { new Notification('YTool', { body: 'Download concluído!' }); } catch (_) {}
    }
  } else if (ev.status === 'error') {
    statusText.textContent = 'Erro';
    appendLog(log, 'ERRO: ' + ev.message);
    showToast(ev.message, 'error');
  }
}

function setDownloadUI(state) {
  const active = state === 'active';
  downloadBtn.disabled = active;
  downloadBtn.innerHTML = active
    ? '<i data-lucide="loader-2" class="w-4 h-4 animate-spin"></i> Baixando...'
    : '<i data-lucide="download" class="w-4 h-4"></i> Baixar';
  lucide.createIcons({ nodes: [downloadBtn] });
  document.getElementById('download-progress-section').classList.remove('hidden');
  if (active) {
    document.getElementById('download-progress-bar').style.width = '0%';
    document.getElementById('download-percent-text').textContent = '0%';
    document.getElementById('download-status-text').textContent = 'Iniciando...';
    document.getElementById('download-log').textContent = '';
    document.getElementById('download-speed-row').classList.add('hidden');
  }
}

function addHistoryEntry(url, outputDir, savedTitle, savedThumb) {
  const list = document.getElementById('download-history');
  const empty = document.getElementById('history-empty');
  if (empty) empty.remove();

  const preview = document.getElementById('preview-thumb');
  const titleEl = document.getElementById('preview-title');
  const thumbSrc = savedThumb || (!savedTitle && preview && preview.src && !preview.src.endsWith('/') ? preview.src : '');
  const title = savedTitle || (titleEl ? titleEl.textContent : '') || url;

  const li = document.createElement('li');
  li.className = 'history-item' + (outputDir ? ' history-item-clickable' : '');
  if (outputDir) {
    li.title = 'Clique para abrir a pasta no Finder';
    li.addEventListener('click', () => openFolder(outputDir));
  }
  li.innerHTML = `
    ${thumbSrc ? `<img src="${escHtml(thumbSrc)}" class="w-16 h-10 object-cover rounded-md flex-shrink-0 bg-gray-800" onerror="this.style.display='none'">` : ''}
    <div class="flex-1 min-w-0">
      <div class="text-gray-200 truncate text-sm">${escHtml(title)}</div>
      ${outputDir ? `<div class="text-gray-600 truncate text-xs mt-0.5">${escHtml(outputDir)}</div>` : ''}
    </div>
    ${outputDir ? '<i data-lucide="folder-open" class="w-4 h-4 text-gray-600 flex-shrink-0 folder-icon"></i>' : '<i data-lucide="check-circle" class="w-4 h-4 text-green-600 flex-shrink-0"></i>'}
  `;
  list.appendChild(li);
  lucide.createIcons({ nodes: [li] });
}

async function clearHistory() {
  try {
    await fetch('/api/history', { method: 'DELETE' });
    const list = document.getElementById('download-history');
    list.innerHTML = `
      <li id="history-empty" class="flex flex-col items-center justify-center py-16 text-gray-700">
        <i data-lucide="inbox" class="w-10 h-10 mb-3 opacity-30"></i>
        <span class="text-sm">Nenhum download ainda</span>
      </li>`;
    lucide.createIcons({ nodes: [list] });
    showToast('Histórico limpo', 'success', 2000);
  } catch (_) {}
}

async function openFolder(path) {
  try {
    const resp = await fetch('/api/config/open-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path }),
    });
    if (!resp.ok) {
      const err = await resp.json();
      showToast(err.error || 'Não foi possível abrir a pasta', 'error');
    }
  } catch (e) {
    showToast('Erro ao abrir a pasta', 'error');
  }
}

// ── Subscriptions ─────────────────────────────────────────────────────────────

async function checkAuthStatus() {
  for (const key of ['source', 'dest']) {
    const resp = await fetch(`/api/subscriptions/status?account_key=${key}`);
    const data = await resp.json();
    const el = document.getElementById(`${key}-status`);
    const card = document.getElementById(`account-card-${key}`);
    el.textContent = data.authenticated ? 'Conectada' : 'Desconectada';
    el.className = `status-badge ${data.authenticated ? 'status-connected' : 'status-disconnected'}`;
    if (card) card.classList.toggle('connected', data.authenticated);
  }
}

function connectAccount(accountKey) {
  return new Promise(resolve => {
    const popup = window.open(
      `/api/subscriptions/oauth/start?account_key=${accountKey}`,
      '_blank', 'width=520,height=640'
    );
    function handler(e) {
      if (e.data === 'oauth_done') {
        window.removeEventListener('message', handler);
        checkAuthStatus();
        syncPlaylistAuthStatus();
        showToast('Conta conectada!', 'success');
        resolve();
      }
    }
    window.addEventListener('message', handler);
    const timer = setInterval(() => {
      if (popup && popup.closed) {
        clearInterval(timer);
        window.removeEventListener('message', handler);
        checkAuthStatus();
        syncPlaylistAuthStatus();
        resolve();
      }
    }, 500);
  });
}

async function exportSubscriptions() {
  const btn = document.getElementById('export-btn');
  btn.disabled = true;
  try {
    const resp = await fetch('/api/subscriptions/export?account_key=source&fmt=json');
    if (!resp.ok) {
      showToast('Falha na exportação: ' + (await resp.json()).error, 'error');
      return;
    }
    const blob = await resp.blob();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'subscriptions.json';
    a.click();
    showToast('Inscrições exportadas!', 'success');
  } finally {
    btn.disabled = false;
  }
}

async function importSubscriptions() {
  const file = document.getElementById('import-file').files[0];
  if (!file) return;
  setSubUI('active', 'Importando...');
  const formData = new FormData();
  formData.append('file', file);
  await streamFormPost('/api/subscriptions/import?account_key=dest', formData, handleSubEvent);
  setSubUI('idle');
}

async function transferSubscriptions() {
  setSubUI('active', 'Transferindo inscrições...');
  await streamPost('/api/subscriptions/transfer?source_key=source&dest_key=dest', {}, handleSubEvent);
  setSubUI('idle');
}

function handleSubEvent(ev) {
  const log = document.getElementById('sub-log');
  const bar = document.getElementById('sub-progress-bar');
  const statusText = document.getElementById('sub-status-text');
  const pctText = document.getElementById('sub-percent-text');

  if (ev.status === 'progress') {
    const pct = ev.total > 0 ? Math.round((ev.done / ev.total) * 100) : 0;
    bar.style.width = pct + '%';
    pctText.textContent = `${ev.done}/${ev.total}`;
    statusText.textContent = `Inscrevendo em ${ev.title || ev.channel_id}...`;
  } else if (ev.status === 'log') {
    appendLog(log, ev.message);
  } else if (ev.status === 'done') {
    bar.style.width = '100%';
    statusText.textContent = `Concluído! ${ev.total} inscrições processadas.`;
    showToast(`${ev.total} inscrições transferidas!`, 'success');
  } else if (ev.status === 'error') {
    appendLog(log, `ERRO (${ev.title || ''}): ${ev.message}`);
  }
}

function setSubUI(state, label) {
  const active = state === 'active';
  ['export-btn', 'import-btn', 'transfer-btn'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.disabled = active;
  });
  document.getElementById('sub-progress-section').classList.toggle('hidden', !active);
  if (active) {
    document.getElementById('sub-progress-bar').style.width = '0%';
    document.getElementById('sub-status-text').textContent = label || 'Processando...';
    document.getElementById('sub-percent-text').textContent = '';
    document.getElementById('sub-log').textContent = '';
  }
}

// ── Playlists ─────────────────────────────────────────────────────────────────

let _loadedPlaylists = [];

async function syncPlaylistAuthStatus() {
  for (const key of ['source', 'dest']) {
    const resp = await fetch(`/api/subscriptions/status?account_key=${key}`);
    const data = await resp.json();
    const el = document.getElementById(`pl-${key}-status`);
    if (el) {
      el.textContent = data.authenticated ? 'Conectada' : 'Desconectada';
      el.className = `status-badge ${data.authenticated ? 'status-connected' : 'status-disconnected'}`;
    }
  }
}

async function loadPlaylists() {
  const btn = document.getElementById('load-playlists-btn');
  btn.innerHTML = '<i data-lucide="loader-2" class="w-3.5 h-3.5 animate-spin"></i> Loading...';
  btn.disabled = true;

  try {
    const resp = await fetch('/api/subscriptions/playlists?account_key=source');
    if (!resp.ok) {
      const err = await resp.json();
      showToast(err.error || 'Falha ao carregar playlists', 'error');
      return;
    }
    const data = await resp.json();
    _loadedPlaylists = data.playlists || [];
    renderPlaylists(_loadedPlaylists);
    document.getElementById('pl-count').textContent = `${_loadedPlaylists.length} playlist(s) encontrada(s)`;
    document.getElementById('playlists-container').classList.remove('hidden');
  } catch (e) {
    showToast('Erro ao carregar playlists: ' + e.message, 'error');
  } finally {
    btn.innerHTML = '<i data-lucide="refresh-cw" class="w-4 h-4"></i> Carregar Playlists da Origem';
    btn.disabled = false;
    lucide.createIcons({ nodes: [btn] });
  }
}

function renderPlaylists(playlists) {
  const list = document.getElementById('playlists-list');
  list.innerHTML = '';

  if (!playlists.length) {
    list.innerHTML = '<p class="text-sm text-gray-600 text-center py-4">Nenhuma playlist encontrada.</p>';
    return;
  }

  const privacyIcon = { public: '🌐', private: '🔒', unlisted: '🔗' };
  const privacyLabel = { public: 'pública', private: 'privada', unlisted: 'não listada' };

  playlists.forEach(pl => {
    const item = document.createElement('label');
    item.className = 'playlist-item';
    item.dataset.id = pl.playlist_id;
    item.innerHTML = `
      <input type="checkbox" class="playlist-checkbox accent-red-500 w-4 h-4 rounded flex-shrink-0"
        value="${escHtml(pl.playlist_id)}" onchange="updateSelectedCount()">
      ${pl.thumbnail
        ? `<img src="${escHtml(pl.thumbnail)}" class="playlist-thumb" alt="" onerror="this.style.display='none'">`
        : '<div class="playlist-thumb bg-gray-800 rounded-md flex-shrink-0"></div>'}
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium text-gray-200 truncate">${escHtml(pl.title)}</div>
        <div class="text-xs text-gray-600 mt-0.5">${privacyIcon[pl.privacy] || ''} ${privacyLabel[pl.privacy] || pl.privacy} · ${pl.video_count} vídeo(s)</div>
      </div>
    `;
    item.querySelector('input').addEventListener('change', () => {
      item.classList.toggle('selected', item.querySelector('input').checked);
    });
    list.appendChild(item);
  });

  updateSelectedCount();
}

function toggleSelectAll() {
  const checked = document.getElementById('select-all-playlists').checked;
  document.querySelectorAll('.playlist-checkbox').forEach(cb => {
    cb.checked = checked;
    cb.closest('.playlist-item').classList.toggle('selected', checked);
  });
  updateSelectedCount();
}

function updateSelectedCount() {
  const total = document.querySelectorAll('.playlist-checkbox:checked').length;
  document.getElementById('selected-count').textContent = `${total} selecionada(s)`;
}

function getSelectedPlaylistIds() {
  return Array.from(document.querySelectorAll('.playlist-checkbox:checked')).map(cb => cb.value);
}

async function transferPlaylists() {
  const ids = getSelectedPlaylistIds();
  if (!ids.length) {
    showToast('Selecione ao menos uma playlist para transferir.', 'info');
    return;
  }

  setPlUI('active', 'Transferindo playlists...');

  await streamPost(
    `/api/subscriptions/playlists/transfer?source_key=source&dest_key=dest`,
    ids,
    handlePlEvent
  );

  setPlUI('idle');
}

function handlePlEvent(ev) {
  const log = document.getElementById('pl-log');
  const statusText = document.getElementById('pl-status-text');
  const pctText = document.getElementById('pl-percent-text');
  const plBar = document.getElementById('pl-playlist-bar');
  const vidBar = document.getElementById('pl-video-bar');
  const plCounter = document.getElementById('pl-playlist-counter');
  const vidCounter = document.getElementById('pl-video-counter');
  const plName = document.getElementById('pl-current-playlist-name');

  if (ev.status === 'playlist_start') {
    const pct = Math.round((ev.playlist_index / ev.playlist_total) * 100);
    plBar.style.width = pct + '%';
    plCounter.textContent = `${ev.playlist_index}/${ev.playlist_total}`;
    plName.textContent = ev.playlist_title;
    vidBar.style.width = '0%';
    vidCounter.textContent = '';
    statusText.textContent = `Criando "${ev.playlist_title}"...`;
  } else if (ev.status === 'progress') {
    const plPct = Math.round((ev.playlist_index / ev.playlist_total) * 100);
    const vidPct = ev.total > 0 ? Math.round((ev.done / ev.total) * 100) : 0;
    plBar.style.width = plPct + '%';
    plCounter.textContent = `${ev.playlist_index}/${ev.playlist_total}`;
    vidBar.style.width = vidPct + '%';
    vidCounter.textContent = `${ev.done}/${ev.total}`;
    plName.textContent = ev.playlist_title;
    statusText.textContent = `Adicionando "${ev.title}"...`;
    pctText.textContent = `${vidPct}%`;
  } else if (ev.status === 'log') {
    appendLog(log, ev.message);
  } else if (ev.status === 'done') {
    plBar.style.width = '100%';
    vidBar.style.width = '100%';
    statusText.textContent = `Concluído! ${ev.total} playlist(s) transferida(s).`;
    pctText.textContent = '100%';
    showToast(`${ev.total} playlist(s) transferida(s)!`, 'success');
  } else if (ev.status === 'error') {
    appendLog(log, `ERRO: ${ev.message}`);
    showToast(ev.message, 'error');
  }
}

function setPlUI(state, label) {
  const active = state === 'active';
  const btn = document.getElementById('transfer-playlists-btn');
  if (btn) btn.disabled = active;
  document.getElementById('pl-progress-section').classList.toggle('hidden', !active);
  if (active) {
    document.getElementById('pl-playlist-bar').style.width = '0%';
    document.getElementById('pl-video-bar').style.width = '0%';
    document.getElementById('pl-status-text').textContent = label || 'Processando...';
    document.getElementById('pl-percent-text').textContent = '';
    document.getElementById('pl-log').textContent = '';
    document.getElementById('pl-playlist-counter').textContent = '';
    document.getElementById('pl-video-counter').textContent = '';
    document.getElementById('pl-current-playlist-name').textContent = '—';
  }
}

// ── Config ────────────────────────────────────────────────────────────────────

let _categories = [];

async function loadConfig() {
  const resp = await fetch('/api/config');
  const data = await resp.json();
  document.getElementById('base-dir-input').value = data.base_download_dir || '';
  _categories = data.categories || [];
  renderCategories();
  populateCategorySelect(_categories);

  const statusEl = document.getElementById('google-status');
  if (data.google_configured) {
    statusEl.textContent = 'Credenciais do Google OAuth configuradas.';
    statusEl.className = 'text-sm px-4 py-3 rounded-xl bg-green-950 border border-green-900 text-green-400';
  } else {
    statusEl.textContent = 'Google OAuth não configurado. Defina GOOGLE_CLIENT_ID e GOOGLE_CLIENT_SECRET no .env.';
    statusEl.className = 'text-sm px-4 py-3 rounded-xl bg-yellow-950 border border-yellow-900 text-yellow-500';
  }
}

function renderCategories() {
  const container = document.getElementById('categories-list');
  container.innerHTML = '';
  _categories.forEach((cat, i) => {
    const div = document.createElement('div');
    div.className = 'flex items-center gap-2';
    div.innerHTML = `
      <span class="flex-1 input py-1.5 text-sm">${escHtml(cat)}</span>
      <button onclick="removeCategory(${i})" class="text-gray-600 hover:text-red-400 transition-colors p-1.5">
        <i data-lucide="x" class="w-3.5 h-3.5"></i>
      </button>`;
    container.appendChild(div);
    lucide.createIcons({ nodes: [div] });
  });
}

function populateCategorySelect(categories) {
  const sel = document.getElementById('category-select');
  const current = sel.value;
  sel.innerHTML = '';
  categories.forEach(cat => {
    const opt = document.createElement('option');
    opt.value = cat;
    opt.textContent = cat;
    if (cat === current) opt.selected = true;
    sel.appendChild(opt);
  });
}

function addCategory() {
  const input = document.getElementById('new-category-input');
  const val = input.value.trim();
  if (!val || _categories.includes(val)) return;
  _categories.push(val);
  input.value = '';
  renderCategories();
  populateCategorySelect(_categories);
  saveConfig();
}

function removeCategory(index) {
  _categories.splice(index, 1);
  renderCategories();
  populateCategorySelect(_categories);
  saveConfig();
}

async function saveConfig() {
  await fetch('/api/config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      base_download_dir: document.getElementById('base-dir-input').value.trim() || null,
      categories: _categories,
    }),
  });
  showToast('Configurações salvas', 'success', 2000);
}

// ── Utilities ──────────────────────────────────────────────────────────────────

function appendLog(el, msg) {
  el.textContent += msg + '\n';
  el.scrollTop = el.scrollHeight;
}

function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Tema claro/escuro ──────────────────────────────────────────────────────────

function toggleTheme() {
  const isLight = document.body.classList.toggle('light');
  localStorage.setItem('ytool-theme', isLight ? 'light' : 'dark');
  const icon = document.getElementById('theme-icon');
  const label = document.getElementById('theme-label');
  if (icon) icon.setAttribute('data-lucide', isLight ? 'moon' : 'sun');
  if (label) label.textContent = isLight ? 'Tema escuro' : 'Tema claro';
  lucide.createIcons({ nodes: [document.getElementById('theme-toggle-btn')] });
}

// ── Modal de Ajuda ─────────────────────────────────────────────────────────────

function openHelp() {
  const modal = document.getElementById('help-modal');
  modal.classList.remove('hidden');
  lucide.createIcons({ nodes: [modal] });
  document.addEventListener('keydown', handleHelpKey);
}

function closeHelp() {
  document.getElementById('help-modal').classList.add('hidden');
  document.removeEventListener('keydown', handleHelpKey);
}

function closeHelpOnOverlay(e) {
  if (e.target === document.getElementById('help-modal')) closeHelp();
}

function handleHelpKey(e) {
  if (e.key === 'Escape') closeHelp();
}

// ── Init ───────────────────────────────────────────────────────────────────────

(async function init() {
  // Aplica tema salvo
  const savedTheme = localStorage.getItem('ytool-theme');
  if (savedTheme === 'light') {
    document.body.classList.add('light');
    const icon = document.getElementById('theme-icon');
    const label = document.getElementById('theme-label');
    if (icon) icon.setAttribute('data-lucide', 'moon');
    if (label) label.textContent = 'Tema escuro';
  }

  lucide.createIcons();
  showTab('downloads');

  const resp = await fetch('/api/config');
  const data = await resp.json();
  _categories = data.categories || [];
  populateCategorySelect(_categories);

  // Carrega histórico persistente
  try {
    const hResp = await fetch('/api/history');
    if (hResp.ok) {
      const history = await hResp.json();
      if (history.length) {
        const empty = document.getElementById('history-empty');
        if (empty) empty.remove();
        history.forEach(h => {
          addHistoryEntry(h.url, h.output_dir, h.title, h.thumbnail);
        });
      }
    }
  } catch (_) {}
})();
