"""Deterministic symptom matcher for the L2 troubleshooting experts.

Ported from logging-l1-triage's match_rca.py. Parses a line-based catalog
(symptoms.txt: one [<symptom-id>] section per known problem, with bare phrase
or "re:" regex lines) and returns the ids whose pattern matches the supplied
text. The text is the expert's diagnostic-pass output (concatenated command
stdout), not a ticket. Standard library only, so it runs wherever python3 is
present. A match is a HINT — the expert reads references/symptoms.md for the
matched id and confirms the condition before using it.
"""
import argparse
import json
import os
import re

_WORD = re.compile(r"\w")


def default_symptoms_path():
    here = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(here, "..", "references", "symptoms.txt")


def _compile_phrase(phrase):
    parts = re.split(r"\s+", phrase.strip())
    body = r"\s+".join(re.escape(p) for p in parts)
    prefix = r"\b" if _WORD.match(phrase[0]) else ""
    suffix = r"\b" if _WORD.match(phrase[-1]) else ""
    return re.compile(prefix + body + suffix, re.IGNORECASE)


def load(path=None):
    """Parse symptoms.txt into {symptom_id: [compiled regex, ...]}."""
    path = path or default_symptoms_path()
    symptoms = {}
    current = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                current = line[1:-1].strip()
                symptoms.setdefault(current, [])
                continue
            if current is None:
                continue
            if line.startswith("re:"):
                symptoms[current].append(re.compile(line[3:].strip(), re.IGNORECASE))
            else:
                symptoms[current].append(_compile_phrase(line))
    return symptoms


def match_text(text, symptoms):
    """Return ids of symptoms with at least one matching pattern, dedup, in order."""
    text = text or ""
    out = []
    seen = set()
    for sid, regexes in symptoms.items():
        if sid in seen:
            continue
        if any(rx.search(text) for rx in regexes):
            seen.add(sid)
            out.append(sid)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Symptom matcher for L2 troubleshooting experts.")
    ap.add_argument("diagnostic_file", help="file with the diagnostic-pass output")
    ap.add_argument("--symptoms", default=None, help="path to symptoms.txt")
    args = ap.parse_args(argv)
    with open(args.diagnostic_file, encoding="utf-8") as fh:
        text = fh.read()
    print(json.dumps(match_text(text, load(args.symptoms)), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
