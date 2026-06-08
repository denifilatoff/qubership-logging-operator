// hooks.js — promptfoo extensions: workdir prep only.
// L1 never touches live systems, so there is no scenario lifecycle: `beforeAll`
// installs the package into .workdir/with-pkg, then dereferences the symlinks
// that a local-path `apm install` leaves behind. No beforeEach/afterAll.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const EVAL_DIR = __dirname;
const REPO_ROOT = path.resolve(EVAL_DIR, '../../../..');
const PKG_DIR = path.join(REPO_ROOT, 'agent-packages/logging-l1-triage');
const WORKDIR_WITH = path.join(EVAL_DIR, '.workdir/with-pkg');

function sh(file, args, opts = {}) {
  return execFileSync(file, args, { stdio: 'inherit', ...opts });
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

function prepWorkdir() {
  fs.rmSync(WORKDIR_WITH, { recursive: true, force: true });
  fs.mkdirSync(WORKDIR_WITH, { recursive: true });
  // Install the package the way a real consumer would.
  sh('apm', ['install', PKG_DIR, '--target', 'claude', '--force'], {
    cwd: WORKDIR_WITH,
  });
  fixSymlinks();
}

async function extensionHook(hookName) {
  if (hookName === 'beforeAll') {
    prepWorkdir();
  }
}

// Export both forms so the `file://hooks.js:extensionHook` reference resolves.
module.exports = extensionHook;
module.exports.extensionHook = extensionHook;
