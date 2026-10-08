// Fugu Dashboard — a webview panel inside the official Claude Code VS Code
// extension's window, for people who never see fugu's terminal HUD/fleet
// view. Thin VS Code wrapper around ../panel/core.js, which does the actual
// data gathering and rendering (shared with the standalone server).
'use strict';
const vscode = require('vscode');
const core = require('./panel-path')('core');

let panel = null;

function config() {
  return vscode.workspace.getConfiguration('fuguStatus');
}

function currentBins() {
  const cfg = config();
  return {
    burn: cfg.get('fuguBurnPath', 'fugu-burn'),
    accounts: cfg.get('fuguAccountsPath', 'fugu-accounts'),
    sessions: cfg.get('fuguSessionsPath', 'fugu-sessions'),
    context: cfg.get('fuguContextPath', 'fugu-context'),
  };
}

function currentProjectFilter() {
  const folders = vscode.workspace.workspaceFolders;
  return folders && folders.length ? folders[0].uri.fsPath : null;
}

async function createOrShowDashboard(context) {
  if (panel) {
    panel.reveal(vscode.ViewColumn.Beside);
    await refreshPanel();
    return;
  }
  panel = vscode.window.createWebviewPanel(
    'fuguDashboard',
    '🐡 Fugu',
    vscode.ViewColumn.Beside,
    { enableScripts: true, retainContextWhenHidden: true }
  );
  panel.onDidDispose(() => { panel = null; });
  panel.webview.onDidReceiveMessage(msg => {
    if (msg && msg.type === 'refresh') refreshPanel();
    if (msg && msg.type === 'regen') refreshPanel({ regen: true });
  });
  context.subscriptions.push(panel);
  await refreshPanel();
}

async function refreshPanel({ regen = false } = {}) {
  if (!panel) return;
  if (!regen) panel.webview.html = '<body style="font-family:sans-serif;padding:16px;">Loading…</body>';
  const data = await core.gatherData({ bins: currentBins(), projectFilter: currentProjectFilter(), regenInsights: regen });
  if (panel) panel.webview.html = core.render(data, { mode: 'vscode', sectionTitle: 'This workspace', themeName: config().get('theme', 'fugu') });
}

module.exports = { createOrShowDashboard, refreshPanel: () => refreshPanel() };
