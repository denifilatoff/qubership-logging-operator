"""Prepare a per-sample workdir: install the skill package, then dereference
the symlinks a local-path `apm install` leaves behind so sandboxed Bash can
read the skills' references and scripts.
"""
import shutil
import subprocess
from pathlib import Path

EVAL_DIR = Path(__file__).parent.parent
REPO_ROOT = (EVAL_DIR / ".." / ".." / ".." / "..").resolve()
PKG_DIR = REPO_ROOT / "agent-packages" / "logging-l1-triage"


def dereference_symlinks(workdir: Path) -> None:
    """Replace any symlink under workdir/.claude/skills with a real copy."""
    skills = workdir / ".claude" / "skills"
    if not skills.exists():
        return
    for path in list(skills.rglob("*")):
        if path.is_symlink():
            target = path.resolve()
            path.unlink()
            if target.is_dir():
                shutil.copytree(target, path)
            else:
                shutil.copy2(target, path)


def prepare_workdir(workdir: Path) -> Path:
    """Fresh workdir + `apm install` + symlink dereference. Returns workdir."""
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True)
    subprocess.run(
        ["apm", "install", str(PKG_DIR), "--target", "claude", "--force"],
        cwd=workdir,
        check=True,
    )
    dereference_symlinks(workdir)
    return workdir
