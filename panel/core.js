// Shared, host-agnostic rendering core for fugu's HTML panels.
// No dependency on vscode or any particular runtime — used by both the
// VS Code extension's webview (vscode-ext/dashboard.js) and the standalone
// local web server (panel/server.js). Read-only: shells out to existing
// fugu-* --json commands and renders what they already compute.
'use strict';
const { execFile } = require('child_process');
const insights = require('./insights');
const { env, fuguBin } = require('./env');

function run(bin, args) {
  return new Promise((resolve, reject) => {
    execFile(bin, args, { timeout: 20000, maxBuffer: 20 * 1024 * 1024, env: env() }, (err, stdout) => {
      if (err) return reject(err);
      try { resolve(JSON.parse(stdout)); } catch (e) { reject(e); }
    });
  });
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

function fmtUsd(n) {
  return `$${(Number(n) || 0).toFixed(2)}`;
}

function relTime(ms) {
  const mins = Math.round((Date.now() - ms) / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.round(hrs / 24)}d`;
}

// bins: { burn, accounts, sessions, context } binary names/paths (default: on PATH)
// projectFilter: substring passed to fugu-context --project (e.g. a workspace path).
//   If omitted, falls back to the most recently active project from fugu-sessions.
// regenInsights: true forces a fresh Haiku call and waits for it (Regenerate
// button). Otherwise a stale cache kicks off a background regeneration and this
// render shows the cached copy, so the 20s poll never blocks on Haiku.
async function gatherData({ bins = {}, projectFilter = null, regenInsights = false } = {}) {
  const fuguBurn = fuguBin('fugu-burn', bins.burn);
  const fuguAccounts = fuguBin('fugu-accounts', bins.accounts);
  const fuguSessions = fuguBin('fugu-sessions', bins.sessions);
  const fuguContext = fuguBin('fugu-context', bins.context);
  bins = { burn: fuguBurn, sessions: fuguSessions };

  const [burn, burnWeek, accounts, sessions, ai] = await Promise.allSettled([
    run(fuguBurn, ['--days', '1', '--json']),
    run(fuguBurn, ['--days', '7', '--json']),
    run(fuguAccounts, ['--json']),
    run(fuguSessions, ['--json']),
    insights.getInsights({ bins, force: regenInsights, allowGenerate: regenInsights }),
  ]);
  const aiValue = ai.status === 'fulfilled' ? ai.value : null;
  if (!regenInsights && aiValue && (aiValue.status === 'stale' || aiValue.status === 'none')) {
    insights.getInsights({ bins }).catch(() => {});
    aiValue.status = 'generating';
  }

  const sessionsList = sessions.status === 'fulfilled' ? sessions.value : null;
  let effectiveFilter = projectFilter;
  if (!effectiveFilter && Array.isArray(sessionsList) && sessionsList.length) {
    effectiveFilter = sessionsList[0].project; // most recently active
  }

  const context = effectiveFilter
    ? await run(fuguContext, ['--project', effectiveFilter, '--json']).then(
        v => ({ status: 'fulfilled', value: v }),
        e => ({ status: 'rejected', reason: e })
      )
    : { status: 'rejected', reason: new Error('no project to show') };

  return {
    burn: burn.status === 'fulfilled' ? burn.value : null,
    ruleInsights: burnWeek.status === 'fulfilled' ? (burnWeek.value.insights || []) : null,
    ai: aiValue,
    accounts: accounts.status === 'fulfilled' ? accounts.value : null,
    sessions: sessionsList,
    context: context.status === 'fulfilled' ? context.value : null,
    errors: [burn, burnWeek, accounts, sessions, context]
      .filter(r => r.status === 'rejected')
      .map(r => (r.reason && r.reason.message) || String(r.reason)),
  };
}

function renderFleetRows(sessions) {
  if (!Array.isArray(sessions) || sessions.length === 0) {
    return '<tr><td colspan="5" class="muted">No sessions found.</td></tr>';
  }
  return sessions.slice(0, 15).map(s => `
    <tr>
      <td>${relTime(s.mtime)}</td>
      <td>${esc(s.projectName || s.project || '')}</td>
      <td class="num">${esc(s.messages)}</td>
      <td class="num">${fmtUsd(s.cost)}</td>
      <td class="title" title="${esc(s.title || '')}">${esc(s.title || s.summary || '')}</td>
    </tr>
  `).join('');
}

function renderAccountRows(accounts) {
  if (!Array.isArray(accounts) || accounts.length === 0) {
    return '<tr><td colspan="4" class="muted">No accounts found.</td></tr>';
  }
  return accounts.map(a => `
    <tr class="${a.active ? 'active-row' : ''}">
      <td>${a.active ? '●' : '·'}</td>
      <td>${esc(a.email || a.profile)}</td>
      <td>${esc(a.plan || '')}</td>
      <td>${esc(a.org || '')}</td>
    </tr>
  `).join('');
}

function renderProjectRows(projects) {
  if (!projects || typeof projects !== 'object') {
    return '<tr><td colspan="3" class="muted">No project data.</td></tr>';
  }
  const rows = Object.entries(projects).sort((a, b) => (b[1].usd || 0) - (a[1].usd || 0));
  return rows.map(([name, p]) => `
    <tr>
      <td>${esc(name)}</td>
      <td class="num">${fmtUsd(p.usd)}</td>
      <td class="num">${esc(p.sessions)}</td>
    </tr>
  `).join('');
}

function renderContextSection(context) {
  if (!context || !context.context) {
    return '<p class="muted">No active Claude Code session detected yet.</p>';
  }
  const ctx = context.context;
  const pct = Math.round((ctx.pct || 0) * 100);
  const top = Array.isArray(ctx.composition)
    ? [...ctx.composition].sort((a, b) => (b.tok || 0) - (a.tok || 0)).slice(0, 6)
    : [];
  return `
    <div class="ctx-header">
      <strong>${esc(context.title || '(untitled)')}</strong>
      <span class="muted"> · ${esc(context.model || '')} · ${esc(context.cwd || '')}</span>
    </div>
    <div class="bar-track"><div class="bar-fill" style="width:${pct}%"></div></div>
    <div class="muted">${pct}% · ${Math.round((ctx.current || 0) / 1000)}k / ${Math.round((ctx.window || 0) / 1000)}k tokens</div>
    <table class="mini">
      ${top.map(c => `<tr><td>${esc(c.cat)}</td><td class="num">≈${Math.round((c.tok || 0) / 1000)}k</td></tr>`).join('')}
    </table>
  `;
}

function renderInsights(data) {
  const ai = data.ai || {};
  let aiHtml;
  if (ai.status === 'haiku-off') {
    aiHtml = '<p class="muted">Haiku insights are off. Turn on with <code>fugu-config set model.haiku on</code>.</p>';
  } else if (Array.isArray(ai.items) && ai.items.length) {
    const when = ai.generatedAt ? `${relTime(Date.parse(ai.generatedAt))} ago` : '';
    aiHtml = ai.items.map(i => `
      <div class="insight">
        <div><strong>${esc(i.title)}</strong></div>
        ${i.pattern ? `<div class="muted">${esc(i.pattern)}</div>` : ''}
        <div>→ ${esc(i.action)}</div>
      </div>`).join('')
      + `<div class="muted small">Written by Haiku ${esc(when)}${ai.status === 'generating' ? ' · refreshing in background' : ''}${Number.isFinite(ai.usd) ? ` · ${fmtUsd(ai.usd)} per run` : ''}. Suggestions, not measurements.</div>`;
  } else if (ai.status === 'generating') {
    aiHtml = '<p class="muted">Haiku is reading your usage patterns… shows up on the next refresh.</p>';
  } else if (ai.status === 'failed') {
    aiHtml = `<p class="muted">Haiku call failed${ai.error ? `: ${esc(ai.error)}` : ''}. Try Regenerate.</p>`;
  } else {
    aiHtml = '<p class="muted">No Haiku insights yet.</p>';
  }

  const rules = Array.isArray(data.ruleInsights) ? data.ruleInsights.slice(0, 4) : [];
  const rulesHtml = rules.length
    ? rules.map(i => `
      <div class="insight">
        <div><strong>${esc(i.title)}</strong> <span class="saving">≈${fmtUsd(i.save)}/mo</span></div>
        <div class="muted">${esc(i.detail)}</div>
        <div>→ ${esc(i.action)}</div>
      </div>`).join('') + '<div class="muted small">Measured from the last 7 days, scaled to 30. Savings overlap; don\'t add them up.</div>'
    : '<p class="muted">No rule-based insights for the last 7 days.</p>';

  return `
    <div class="insights-head">
      <h3>Patterns (Haiku)</h3>
      <button onclick="regen()">Regenerate</button>
    </div>
    ${aiHtml}
    <h3>Biggest levers (measured)</h3>
    ${rulesHtml}`;
}

// mode: 'vscode' (default) wires the Refresh button to acquireVsCodeApi()
// postMessage, matching dashboard.js's onDidReceiveMessage handler.
// 'http' wires it to a plain location.reload() and adds a meta auto-refresh
// tag, for the standalone server with no extension host to message.
function render(data, { mode = 'vscode', refreshSeconds = 20, sectionTitle = 'This workspace' } = {}) {
  const burnA = data.burn && data.burn.A ? data.burn.A : null;
  const refreshScript = mode === 'http'
    ? `function refresh() { location.reload(); }
       function regen() { const u = new URL(location.href); u.searchParams.set('regen', '1'); document.body.style.opacity = 0.5; location.href = u.toString(); }`
    : `const vscode = acquireVsCodeApi();
       function refresh() { vscode.postMessage({ type: 'refresh' }); }
       function regen() { document.body.style.opacity = 0.5; vscode.postMessage({ type: 'regen' }); }`;
  const autoRefreshMeta = mode === 'http' ? `<meta http-equiv="refresh" content="${refreshSeconds}">` : '';
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
${autoRefreshMeta}
<title>Fugu Dashboard</title>
<style>
  :root {
    --fg: var(--vscode-foreground, #d4d4d4);
    --bg: var(--vscode-editor-background, #1e1e1e);
    --border: var(--vscode-widget-border, #3c3c3c);
    --muted: var(--vscode-descriptionForeground, #9a9a9a);
    --accent: var(--vscode-progressBar-background, #0a84ff);
    --btn-bg: var(--vscode-button-background, #0a84ff);
    --btn-fg: var(--vscode-button-foreground, #ffffff);
    --btn-hover: var(--vscode-button-hoverBackground, #0870d8);
    --err: var(--vscode-errorForeground, #f14c4c);
  }
  body {
    font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
    color: var(--fg);
    background: var(--bg);
    padding: 16px;
    font-size: 13px;
    max-width: 900px;
    margin: 0 auto;
  }
  h1 { font-size: 16px; margin: 0 0 12px; }
  h2 { margin: 20px 0 8px; font-size: 14px; border-bottom: 1px solid var(--border); padding-bottom: 4px; }
  h2:first-of-type { margin-top: 0; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
  td, th { padding: 3px 8px 3px 0; text-align: left; vertical-align: top; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .muted { color: var(--muted); }
  .title { max-width: 360px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .active-row { font-weight: 600; }
  .bar-track { background: var(--border); border-radius: 3px; height: 8px; overflow: hidden; margin: 6px 0 4px; }
  .bar-fill { background: var(--accent); height: 100%; }
  .summary { display: flex; gap: 24px; margin-bottom: 4px; }
  .summary .stat { font-size: 20px; font-weight: 600; }
  .summary .label { font-size: 11px; color: var(--muted); }
  .mini td { padding: 1px 8px 1px 0; font-size: 12px; }
  button { background: var(--btn-bg); color: var(--btn-fg); border: none; padding: 4px 10px; border-radius: 3px; cursor: pointer; }
  button:hover { background: var(--btn-hover); }
  .errors { color: var(--err); font-size: 11px; margin-top: 16px; }
  h3 { font-size: 12px; margin: 10px 0 4px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--muted); }
  .insights-head { display: flex; justify-content: space-between; align-items: center; }
  .insight { margin: 0 0 8px; line-height: 1.4; }
  .saving { color: var(--accent); font-weight: 600; font-size: 12px; }
  .small { font-size: 11px; margin-bottom: 4px; }
  code { font-size: 12px; }
  a { color: var(--accent); }
</style>
</head>
<body>
  <h1>🐡 fugu</h1>
  <div style="display:flex; justify-content:space-between; align-items:center;">
    <div class="summary">
      <div><div class="stat">${burnA ? fmtUsd(burnA.usd) : '—'}</div><div class="label">today, all projects</div></div>
      <div><div class="stat">${burnA ? burnA.sessions : '—'}</div><div class="label">sessions today</div></div>
      <div><div class="stat">${burnA ? burnA.reqs : '—'}</div><div class="label">requests today</div></div>
    </div>
    <button onclick="refresh()">Refresh</button>
  </div>

  <h2>Insights</h2>
  ${renderInsights(data)}

  <h2>${esc(sectionTitle)}</h2>
  ${renderContextSection(data.context)}

  <h2>Cost by project (today)</h2>
  <table>
    <tr><th>Project</th><th class="num">Cost</th><th class="num">Sessions</th></tr>
    ${renderProjectRows(burnA ? burnA.projects : null)}
  </table>

  <h2>Recent sessions (fleet)</h2>
  <table>
    <tr><th>Last active</th><th>Project</th><th class="num">Msgs</th><th class="num">Cost</th><th>Title</th></tr>
    ${renderFleetRows(data.sessions)}
  </table>

  <h2>Accounts</h2>
  <table>
    <tr><th></th><th>Email</th><th>Plan</th><th>Org</th></tr>
    ${renderAccountRows(data.accounts)}
  </table>

  ${data.errors && data.errors.length ? `<div class="errors">Some data failed to load: ${esc(data.errors.join('; '))}</div>` : ''}

  <script>${refreshScript}</script>
</body>
</html>`;
}

module.exports = { gatherData, render, esc, fmtUsd, relTime };
