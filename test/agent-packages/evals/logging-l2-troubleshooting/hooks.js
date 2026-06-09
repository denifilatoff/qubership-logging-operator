// hooks.js — promptfoo extensions: workdir prep + scenario lifecycle.
// Replaces prep-workdir.sh and orchestrator.sh's apply/revert loop.
// Bash stays in the scenario layer; this only *calls* fixture.sh.
const { execFileSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const EVAL_DIR = __dirname;
const REPO_ROOT = path.resolve(EVAL_DIR, '../../../..');
const PKG_DIR = path.join(REPO_ROOT, 'agent-packages/logging-l2-troubleshooting');
const FIXTURE = path.join(REPO_ROOT, 'test/agent-packages/scenarios/fixture.sh');
const WORKDIR_WITH = path.join(EVAL_DIR, '.workdir/with-pkg');
const WORKDIR_NO = path.join(EVAL_DIR, '.workdir/no-pkg');

function sh(file, args, opts = {}) {
  return execFileSync(file, args, { stdio: 'inherit', ...opts });
}
function fixture(cmd, slug) {
  return execFileSync('bash', [FIXTURE, cmd, slug].filter(Boolean), {
    encoding: 'utf8',
  });
}

// apm install drops symlink targets under .apm/skills/<name>/{references,scripts}
// on a local-path install; dereference them into the deployed tree (cp -L).
function fixSymlinks() {
  const srcSkills = path.join(PKG_DIR, '.apm/skills');
  const dstSkills = path.join(WORKDIR_WITH, '.claude/skills');
  if (!fs.existsSync(dstSkills)) return;
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isSymbolicLink()) {
        const rel = path.relative(srcSkills, p);
        const dst = path.join(dstSkills, rel);
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        fs.copyFileSync(fs.realpathSync(p), dst); // cp -L
      } else if (e.isDirectory()) {
        walk(p);
      }
    }
  };
  walk(srcSkills);
}

function prepWorkdirs() {
  for (const w of [WORKDIR_WITH, WORKDIR_NO]) {
    fs.rmSync(w, { recursive: true, force: true });
    fs.mkdirSync(w, { recursive: true });
  }
  // with-pkg: install the package the way a real consumer would.
  sh('apm', ['install', PKG_DIR, '--target', 'claude', '--force'], {
    cwd: WORKDIR_WITH,
  });
  fixSymlinks();
  // no-pkg stays empty (control branch, currently disabled in config).
}

// `fixture.sh status` exits non-zero when a fixture is active (its existing
// query convention), so the exit code alone can't tell "active" from "the
// status query itself failed". Decide on the stdout text instead, and fail
// loud on anything unrecognized: a silent null here once let teardown skip its
// revert and leave the cluster on a bad image (missing deploy/kind/.env, or
// fixture.sh gone after a branch switch). A dirty cluster must abort the run,
// not pass quietly.
function activeScenario() {
  const r = spawnSync('bash', [FIXTURE, 'status'], { encoding: 'utf8' });
  const out = r.stdout || '';
  const m = out.match(/active:\s*(\S+)/);
  if (m) return m[1]; // a fixture is active
  if (/no fixtures active/.test(out)) return null; // clean baseline
  throw new Error(
    `fixture.sh status returned no recognizable state (exit ${r.status}); ` +
      `the cluster's cleanliness is unknown, so the run is aborting rather than ` +
      `risk leaving a fixture applied.\n` +
      `stdout: ${out.trim() || '(empty)'}\n` +
      `stderr: ${(r.stderr || '').trim() || '(empty)'}`,
  );
}

async function extensionHook(hookName, context) {
  if (hookName === 'beforeAll') {
    prepWorkdirs();
  }
  if (hookName === 'beforeEach') {
    const slug = context.test.vars.case;
    const active = activeScenario();
    if (active === slug) return; // repeat 2..N — already applied, no-op
    if (active) fixture('revert', active); // different case still up — clean it
    fixture('apply', slug);
  }
  if (hookName === 'afterAll') {
    const active = activeScenario();
    if (active) fixture('revert', active);
  }
}

// Export both the default and a named property so the promptfoo `extensions`
// reference (file://hooks.js:extensionHook) resolves whichever form it expects.
module.exports = extensionHook;
module.exports.extensionHook = extensionHook;
