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

const k = n => { n = Number(n) || 0; return n < 1000 ? String(Math.round(n)) : n < 10000 ? `${(n / 1000).toFixed(1)}k` : `${Math.round(n / 1000)}k`; };
const STATUS = { warning: '#fab219', critical: '#d03b3b' };

function empty(text) {
  return `<p class="empty">${esc(text)}</p>`;
}

function renderKpis(A, data) {
  const tiles = [
    ['Spend today', A ? fmtUsd(A.usd) : '—', 'API list price, all projects'],
    ['Sessions', A ? A.sessions : '—', 'active today'],
    ['Requests', A ? Number(A.reqs).toLocaleString() : '—', 'model calls today'],
  ];
  const lever = Array.isArray(data.ruleInsights) && data.ruleInsights[0];
  if (lever) tiles.push(['Top lever', `≈${fmtUsd(lever.save)}/mo`, lever.title]);
  return `<div class="kpis">${tiles.map(([label, value, sub]) => `
    <div class="tile"><div class="tile-label">${esc(label)}</div><div class="tile-value">${esc(value)}</div><div class="tile-sub">${esc(sub)}</div></div>`).join('')}
  </div>`;
}

function renderContext(context, sectionTitle) {
  if (!context || !context.context) return card(sectionTitle, empty('No Claude Code session found for this workspace yet.'));
  const ctx = context.context;
  const pct = Math.round((ctx.pct || 0) * 100);
  const ac = ctx.autocompactPct || 80;
  const state = pct >= ac ? 'critical' : pct >= ac - 20 ? 'warning' : 'ok';
  const badge = state === 'critical' ? `<span class="badge critical">🔥 near autocompact</span>`
    : state === 'warning' ? `<span class="badge warning">⚠ filling up</span>` : `<span class="badge ok">✓ room to work</span>`;
  const fill = state === 'ok' ? 'var(--series)' : STATUS[state];
  const comp = Array.isArray(ctx.composition) ? [...ctx.composition].sort((a, b) => (b.tok || 0) - (a.tok || 0)).slice(0, 5) : [];
  const maxTok = Math.max(1, ...comp.map(c => c.tok || 0));
  const body = `
    <div class="ctx-title" title="${esc(context.cwd || '')}">${esc(context.title || 'Current session')}</div>
    <div class="ctx-meta"><span class="chip">${esc(context.model || 'model?')}</span><span class="dim">${esc(context.cwd || '')}</span></div>
    <div class="meter" title="${pct}% of ${k(ctx.window)} context window used; autocompact at ${ac}%">
      <div class="meter-fill" style="width:${Math.min(100, pct)}%;background:${fill}"></div>
      <div class="meter-mark" style="left:${ac}%"></div>
    </div>
    <div class="meter-row"><span><strong>${pct}%</strong> <span class="dim">${k(ctx.current)} / ${k(ctx.window)} tokens</span></span>${badge}</div>
    ${comp.length ? `<div class="sub-head">What's filling it</div>
    <div class="bars">${comp.map(c => barRow(c.cat, (c.tok || 0) / maxTok, `≈${k(c.tok)}`, `${c.cat}: about ${k(c.tok)} tokens`)).join('')}</div>` : ''}`;
  return card(sectionTitle, body);
}

function barRow(label, frac, value, tip) {
  return `<div class="bar-row" title="${esc(tip)}">
    <div class="bar-label">${esc(label)}</div>
    <div class="bar-track"><div class="bar" style="width:${Math.max(1.5, frac * 100).toFixed(1)}%"></div></div>
    <div class="bar-value">${esc(value)}</div>
  </div>`;
}

function renderInsights(data) {
  const ai = data.ai || {};
  let aiHtml;
  if (ai.status === 'haiku-off') {
    aiHtml = empty('Haiku insights are off. Turn on with: fugu-config set model.haiku on');
  } else if (Array.isArray(ai.items) && ai.items.length) {
    const when = ai.generatedAt ? `${relTime(Date.parse(ai.generatedAt))} ago` : '';
    aiHtml = `<div class="insights">${ai.items.map(i => `
      <div class="insight">
        <div class="insight-title">${esc(i.title)}</div>
        ${i.pattern ? `<div class="insight-pattern">${esc(i.pattern)}</div>` : ''}
        <div class="insight-action"><span class="arrow">→</span>${esc(i.action)}</div>
      </div>`).join('')}</div>
      <div class="foot">Written by Haiku ${esc(when)}${ai.status === 'generating' ? ' · refreshing in background' : ''}${Number.isFinite(ai.usd) ? ` · ${fmtUsd(ai.usd)} per run` : ''} · suggestions, not measurements</div>`;
  } else if (ai.status === 'generating') {
    aiHtml = empty('Haiku is reading your usage patterns. They show up on a refresh in about a minute.');
  } else if (ai.status === 'failed') {
    aiHtml = empty(`Haiku call failed${ai.error ? `: ${ai.error}` : ''}. Try Regenerate.`);
  } else {
    aiHtml = empty('No Haiku insights yet.');
  }

  const rules = Array.isArray(data.ruleInsights) ? data.ruleInsights.slice(0, 5) : [];
  const rulesHtml = rules.length
    ? `<div class="levers">${rules.map(i => `
      <details class="lever">
        <summary><span class="lever-title">${esc(i.title)}</span><span class="pill">≈${fmtUsd(i.save)}/mo</span></summary>
        <div class="insight-pattern">${esc(i.detail)}</div>
        <div class="insight-action"><span class="arrow">→</span>${esc(i.action)}</div>
      </details>`).join('')}</div>
      <div class="foot">Measured over the last 7 days, scaled to 30. Savings overlap, so don't add them up.</div>`
    : empty('No measured levers for the last 7 days.');

  return card('Insights', `
    <div class="sub-head row"><span>Patterns · Haiku</span><button class="ghost" onclick="regen()">↻ Regenerate</button></div>
    ${aiHtml}
    <div class="sub-head">Biggest levers · measured</div>
    ${rulesHtml}`);
}

function renderProjects(A) {
  const entries = A ? Object.entries(A.projects || {}).sort((a, b) => (b[1].usd || 0) - (a[1].usd || 0)) : [];
  if (!entries.length) return card('Cost by project · today', empty('No spend yet today.'));
  const shown = entries.slice(0, 7);
  const rest = entries.slice(7);
  if (rest.length) shown.push([`Other (${rest.length})`, { usd: rest.reduce((s, [, p]) => s + (p.usd || 0), 0), sessions: rest.reduce((s, [, p]) => s + (p.sessions || 0), 0) }]);
  const max = Math.max(...shown.map(([, p]) => p.usd || 0), 0.01);
  return card('Cost by project · today', `<div class="bars">${shown.map(([name, p]) =>
    barRow(name, (p.usd || 0) / max, fmtUsd(p.usd), `${name}: ${fmtUsd(p.usd)} across ${p.sessions} session${p.sessions === 1 ? '' : 's'}`)).join('')}</div>`);
}

function renderSessions(sessions) {
  if (!Array.isArray(sessions) || !sessions.length) return card('Recent sessions', empty('No sessions found.'));
  return card('Recent sessions', `<div class="sessions">${sessions.slice(0, 12).map(s => {
    const live = s.status === 'active';
    return `<div class="session" title="${esc(s.resume || '')}">
      <span class="dot ${live ? 'live' : ''}" aria-label="${live ? 'active' : 'idle'}"></span>
      <div class="session-main">
        <div class="session-title">${esc(s.title || s.summary || '(untitled)')}</div>
        <div class="session-meta">${esc(s.projectName || '')} · ${esc(s.messages)} msgs · ${relTime(s.mtime)}${live ? ' · active' : ''}</div>
      </div>
      <div class="session-cost">${fmtUsd(s.cost)}</div>
    </div>`;
  }).join('')}</div>`);
}

function renderAccounts(accounts) {
  if (!Array.isArray(accounts) || !accounts.length) return card('Accounts', empty('No accounts found.'));
  return card('Accounts', `<div class="accounts">${accounts.map(a => `
    <div class="account ${a.active ? 'active' : ''}" title="${esc(a.org || '')}">
      <div class="account-email">${a.active ? '● ' : ''}${esc(a.email || a.profile)}</div>
      <div class="account-meta"><span class="chip">${esc(a.plan || '?')}</span>${esc(a.org || '')}</div>
    </div>`).join('')}</div>`);
}

function card(title, body) {
  return `<section class="card"><h2>${esc(title)}</h2>${body}</section>`;
}

// mode: 'vscode' (default) wires the buttons to acquireVsCodeApi() postMessage,
// matching the onDidReceiveMessage handlers in dashboard.js and sidebar-view.js.
// 'http' wires them to page loads and adds a meta auto-refresh, for the
// standalone server with no extension host to message.
function render(data, { mode = 'vscode', refreshSeconds = 20, sectionTitle = 'This workspace' } = {}) {
  const A = data.burn && data.burn.A ? data.burn.A : null;
  const refreshScript = mode === 'http'
    ? `function refresh() { location.reload(); }
       function regen() { const u = new URL(location.href); u.searchParams.set('regen', '1'); document.body.classList.add('busy'); location.href = u.toString(); }`
    : `const vscode = acquireVsCodeApi();
       function refresh() { document.body.classList.add('busy'); vscode.postMessage({ type: 'refresh' }); }
       function regen() { document.body.classList.add('busy'); vscode.postMessage({ type: 'regen' }); }`;
  const autoRefreshMeta = mode === 'http' ? `<meta http-equiv="refresh" content="${refreshSeconds}">` : '';
  const updated = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${autoRefreshMeta}
<title>🐡 fugu</title>
<style>
  :root {
    --fb-bg: #fcfcfb; --fb-plane: #f9f9f7; --fb-fg: #0b0b0b; --fb-muted: #52514e; --fb-border: #e4e3de; --fb-series: #2a78d6; --fb-track: #ecebe6;
    --bg: var(--vscode-sideBar-background, var(--vscode-editor-background, var(--fb-plane)));
    --card: var(--vscode-editorWidget-background, var(--fb-bg));
    --fg: var(--vscode-foreground, var(--fb-fg));
    --muted: var(--vscode-descriptionForeground, var(--fb-muted));
    --border: var(--vscode-widget-border, var(--vscode-panel-border, var(--fb-border)));
    --series: var(--vscode-charts-blue, var(--fb-series));
    --track: var(--vscode-editorWidget-border, var(--fb-track));
    --btn-bg: var(--vscode-button-background, var(--fb-series));
    --btn-fg: var(--vscode-button-foreground, #ffffff);
    --btn-hover: var(--vscode-button-hoverBackground, #1f63b5);
    --err: var(--vscode-errorForeground, #d03b3b);
  }
  @media (prefers-color-scheme: dark) {
    :root { --fb-bg: #1a1a19; --fb-plane: #0d0d0d; --fb-fg: #ffffff; --fb-muted: #c3c2b7; --fb-border: #2e2e2c; --fb-series: #3987e5; --fb-track: #2a2a28; }
  }
  * { box-sizing: border-box; }
  body {
    font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
    font-size: 13px; line-height: 1.45; color: var(--fg); background: var(--bg);
    margin: 0; padding: 12px; transition: opacity .15s;
  }
  body.busy { opacity: .55; pointer-events: none; }
  .wrap { max-width: 960px; margin: 0 auto; display: grid; gap: 12px; }
  header { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  header h1 { font-size: 16px; margin: 0; letter-spacing: -.01em; }
  header .dim { font-size: 11px; }
  .dim { color: var(--muted); }
  .kpis { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
  @media (min-width: 640px) { .kpis { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
  .tile { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 10px 12px; min-width: 0; }
  .tile-label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .05em; }
  .tile-value { font-size: 22px; font-weight: 650; font-variant-numeric: tabular-nums; margin: 2px 0; white-space: nowrap; }
  .tile-sub { font-size: 11px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .card { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 12px 14px; min-width: 0; }
  .card h2 { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 0 0 10px; }
  .sub-head { font-size: 11px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .05em; margin: 14px 0 6px; }
  .sub-head:first-child { margin-top: 0; }
  .sub-head.row { display: flex; justify-content: space-between; align-items: center; }
  .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 12px; }
  .grid-2 > *, .levers > *, .insights > *, .bars > * { min-width: 0; }
  .ctx-title { font-weight: 600; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ctx-meta { display: flex; gap: 8px; align-items: center; margin: 4px 0 10px; font-size: 11px; min-width: 0; }
  .ctx-meta .dim { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .chip { display: inline-block; font-size: 11px; padding: 1px 7px; border-radius: 999px; border: 1px solid var(--border); color: var(--fg); white-space: nowrap; margin-right: 6px; }
  .meter { position: relative; height: 10px; border-radius: 5px; background: var(--track); overflow: hidden; }
  .meter-fill { height: 100%; border-radius: 5px; }
  .meter-mark { position: absolute; top: -2px; bottom: -2px; width: 2px; background: var(--fg); opacity: .45; }
  .meter-row { display: flex; justify-content: space-between; align-items: center; margin-top: 6px; gap: 8px; flex-wrap: wrap; }
  .badge { font-size: 11px; padding: 1px 8px; border-radius: 999px; border: 1px solid currentColor; white-space: nowrap; }
  .badge.ok { color: var(--muted); }
  .badge.warning { color: ${STATUS.warning}; }
  .badge.critical { color: ${STATUS.critical}; }
  .bars { display: grid; gap: 6px; }
  .bar-row { display: grid; grid-template-columns: minmax(70px, 34%) 1fr auto; align-items: center; gap: 8px; }
  .bar-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; }
  .bar-track { height: 8px; }
  .bar { height: 8px; background: var(--series); border-radius: 0 4px 4px 0; }
  .bar-row:hover .bar { filter: brightness(1.15); }
  .bar-value { font-size: 12px; font-variant-numeric: tabular-nums; text-align: right; min-width: 52px; }
  .insights { display: grid; gap: 8px; }
  .insight { border-left: 3px solid var(--series); padding: 2px 0 2px 10px; }
  .insight-title { font-weight: 600; }
  .insight-pattern { color: var(--muted); font-size: 12px; margin-top: 2px; }
  .insight-action { margin-top: 3px; font-size: 12px; }
  .arrow { color: var(--series); font-weight: 700; margin-right: 6px; }
  .levers { display: grid; gap: 4px; }
  .lever { border: 1px solid var(--border); border-radius: 6px; padding: 6px 10px; }
  .lever summary { min-width: 0; display: flex; justify-content: space-between; align-items: center; gap: 8px; cursor: pointer; list-style: none; }
  .lever summary::-webkit-details-marker { display: none; }
  .lever summary::before { content: '▸'; color: var(--muted); margin-right: 6px; transition: transform .15s; }
  .lever[open] summary::before { transform: rotate(90deg); }
  .lever-title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .lever[open] .insight-pattern { margin-top: 6px; }
  .pill { font-size: 11px; font-weight: 600; font-variant-numeric: tabular-nums; padding: 1px 8px; border-radius: 999px; background: var(--track); white-space: nowrap; }
  .foot { font-size: 11px; color: var(--muted); margin-top: 8px; }
  .sessions { display: grid; }
  .session { display: grid; grid-template-columns: 10px 1fr auto; gap: 10px; align-items: center; padding: 6px 0; border-top: 1px solid var(--border); }
  .session:first-child { border-top: 0; padding-top: 0; }
  .session-main { min-width: 0; }
  .session-title { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .session-meta { font-size: 11px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .session-cost { font-variant-numeric: tabular-nums; font-size: 12px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; border: 1.5px solid var(--muted); }
  .dot.live { background: #0ca30c; border-color: #0ca30c; }
  .accounts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr)); gap: 8px; }
  .account { border: 1px solid var(--border); border-radius: 6px; padding: 6px 10px; min-width: 0; }
  .account.active { border-color: var(--series); }
  .account-email { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .account-meta { font-size: 11px; color: var(--muted); margin-top: 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .empty { color: var(--muted); margin: 0; font-size: 12px; }
  button { font: inherit; font-size: 12px; background: var(--btn-bg); color: var(--btn-fg); border: none; padding: 4px 10px; border-radius: 4px; cursor: pointer; }
  button:hover { background: var(--btn-hover); }
  button.ghost { background: transparent; color: var(--series); padding: 2px 6px; text-transform: none; letter-spacing: 0; }
  button.ghost:hover { background: var(--track); }
  .errors { color: var(--err); font-size: 11px; }
  @media (max-width: 360px) {
    body { padding: 8px; }
    .tile-value { font-size: 18px; }
    .bar-row { grid-template-columns: 1fr auto; }
    .bar-row .bar-track { grid-column: 1 / -1; grid-row: 2; }
  }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>🐡 fugu</h1>
    <div><span class="dim">updated ${esc(updated)}</span> <button onclick="refresh()">Refresh</button></div>
  </header>
  ${renderKpis(A, data)}
  <div class="grid-2">
    ${renderContext(data.context, sectionTitle)}
    ${renderProjects(A)}
  </div>
  ${renderInsights(data)}
  <div class="grid-2">
    ${renderSessions(data.sessions)}
    ${renderAccounts(data.accounts)}
  </div>
  ${data.errors && data.errors.length ? `<div class="errors">Some data failed to load: ${esc(data.errors.join('; '))}</div>` : ''}
</div>
<script>${refreshScript}</script>
</body>
</html>`;
}

module.exports = { gatherData, render, esc, fmtUsd, relTime };
