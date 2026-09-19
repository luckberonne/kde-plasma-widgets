#!/bin/sh
# Uso: history.sh <ruta-del-proyecto> [cantidad]
# Lista las últimas sesiones de Claude Code de esa carpeta:
# SESSION <id> <mtime> <título = primer mensaje del usuario>
P="$1"
N="${2:-12}"
ENC=$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')
DIR="$HOME/.claude/projects/$ENC"
[ -d "$DIR" ] || exit 0
ls -t "$DIR"/*.jsonl 2>/dev/null | head -n "$N" | python3 -c '
import json, os, sys
for path in sys.stdin.read().split("\n"):
    if not path:
        continue
    title = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 600:
                    break
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("type") != "user" or o.get("isMeta"):
                    continue
                c = (o.get("message") or {}).get("content")
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                if not isinstance(c, str):
                    continue
                c = " ".join(c.split())
                if c and not c.startswith("<"):
                    title = c[:110]
                    break
    except OSError:
        continue
    sid = os.path.basename(path)[:-6]
    print("SESSION\t%s\t%d\t%s" % (sid, os.path.getmtime(path), title or "(sin título)"))
'
