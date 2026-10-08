// GUI-launched hosts (VS Code's extension host, LaunchAgents) don't get the
// login shell's PATH, so bare `fugu-burn` or `claude` can fail with ENOENT.
// Resolve fugu's own commands from this repo and widen PATH for node/claude.
'use strict';
const path = require('path');
const os = require('os');

const FUGU_BIN = path.join(__dirname, '..', 'bin');
const EXTRA = [FUGU_BIN, '/opt/homebrew/bin', '/usr/local/bin', path.join(os.homedir(), '.local', 'bin')];

const env = () => ({ ...process.env, PATH: [...EXTRA, process.env.PATH || '/usr/bin:/bin'].join(':') });

// A configured value that is a bare fugu-* name resolves to this repo's bin/.
const fuguBin = (name, configured) =>
  !configured || configured === name ? path.join(FUGU_BIN, name) : configured;

module.exports = { env, fuguBin, FUGU_BIN };
