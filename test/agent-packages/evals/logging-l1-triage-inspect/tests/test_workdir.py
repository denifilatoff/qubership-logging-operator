import os
from pathlib import Path
from harness.workdir import dereference_symlinks


def test_dereferences_symlinked_files(tmp_path):
    real = tmp_path / "src" / "references"
    real.mkdir(parents=True)
    (real / "signals.txt").write_text("DATA")

    skills = tmp_path / "dst" / ".claude" / "skills" / "logging-l1-classification"
    skills.mkdir(parents=True)
    link = skills / "references"
    os.symlink(real, link)

    dereference_symlinks(tmp_path / "dst")

    assert not (skills / "references").is_symlink()
    assert (skills / "references" / "signals.txt").read_text() == "DATA"
