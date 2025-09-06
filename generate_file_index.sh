#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate_file_index.sh [OUTPUT]
OUT=${1:-file_index.json}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository. Aborting." >&2
  exit 1
fi

# Run an embedded Python snippet to reliably build JSON
python3 - "$OUT" <<'PY'
import json, subprocess, sys, os

out = sys.argv[1] if len(sys.argv) > 1 else "file_index.json"

# get tracked files
files = subprocess.check_output(["git", "ls-files"]).decode("utf-8").splitlines()

result = []
for f in files:
    # blob sha from ls-files -s
    try:
        sha_line = subprocess.check_output(["git", "ls-files", "-s", "--", f]).decode("utf-8").strip()
        # format: <mode> <sha> <stage>\t<path>
        parts = sha_line.split()
        sha = parts[1] if len(parts) > 1 else ""
    except subprocess.CalledProcessError:
        sha = ""

    # size via git cat-file -s <sha> (fallback to filesystem size)
    size = None
    if sha:
        try:
            size = int(subprocess.check_output(["git", "cat-file", "-s", sha]).decode("utf-8").strip())
        except Exception:
            size = None
    if size is None:
        try:
            size = os.path.getsize(f)
        except Exception:
            size = None

    # last commit info for path: hash | iso-date | author
    try:
        info = subprocess.check_output(["git", "log", "-1", "--format=%H%x01%ci%x01%an", "--", f]).decode("utf-8").strip()
        if info:
            h, date, author = info.split("\x01")
        else:
            h = date = author = ""
    except subprocess.CalledProcessError:
        h = date = author = ""

    result.append({
        "path": f,
        "sha": sha,
        "size": size if isinstance(size, int) else None,
        "last_commit": h,
        "last_commit_date": date,
        "author": author
    })

# write pretty JSON (UTF-8)
with open(out, "w", encoding="utf-8") as fp:
    json.dump(result, fp, ensure_ascii=False, indent=2)

print("Wrote", out)
PY