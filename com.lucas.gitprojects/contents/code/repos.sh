#!/bin/sh
# Uso: repos.sh <carpeta-raíz> [profundidad]
# Imprime una línea REPO por repositorio Git encontrado (campos separados por tabulador):
# REPO nombre ruta rama cambios ahead behind tieneRemoto codeOssTs claudeSesiones claudeTs ultimoCommitTs asunto
ROOT="$1"
DEPTH="${2:-3}"
case "$ROOT" in "~"*) ROOT="$HOME${ROOT#\~}" ;; esac
[ -d "$ROOT" ] || { printf 'ERROR\tNo existe la carpeta %s\n' "$ROOT"; exit 0; }

# Historial de code-oss: carpeta abierta -> última vez (mtime de su almacenamiento de workspace)
OSS_DIR="$HOME/.config/Code - OSS/User/workspaceStorage"
OSS_MAP=""
if [ -d "$OSS_DIR" ]; then
    OSS_MAP=$(for w in "$OSS_DIR"/*/workspace.json; do
        [ -r "$w" ] || continue
        f=$(sed -n 's/.*"folder": *"file:\/\/\([^"]*\)".*/\1/p' "$w")
        [ -n "$f" ] || continue
        t=$(stat -c %Y "$(dirname "$w")/state.vscdb" 2>/dev/null || stat -c %Y "$(dirname "$w")")
        printf '%s\t%s\n' "$t" "$f"
    done)
fi

find "$ROOT" -maxdepth "$DEPTH" \( -name node_modules -o -name .cache -o -name .venv \) -prune -o -name .git -print 2>/dev/null | sort | while read -r g; do
    d=$(dirname "$g")
    st=$(git -C "$d" status --porcelain=v2 --branch 2>/dev/null) || continue
    branch=$(printf '%s\n' "$st" | sed -n 's/^# branch\.head //p')
    ab=$(printf '%s\n' "$st" | sed -n 's/^# branch\.ab //p')
    upstream=$(printf '%s\n' "$st" | sed -n 's/^# branch\.upstream //p')
    changes=$(printf '%s\n' "$st" | grep -vc '^#')
    ahead=0; behind=0
    if [ -n "$ab" ]; then
        ahead=${ab%% *}; ahead=${ahead#+}
        behind=${ab##* }; behind=${behind#-}
    fi

    # code-oss: la entrada más reciente para esta carpeta
    oss=0
    [ -n "$OSS_MAP" ] && oss=$(printf '%s\n' "$OSS_MAP" | awk -F'\t' -v p="$d" '$2==p && $1>m {m=$1} END {print m+0}')

    # Claude Code: sesiones guardadas para esta carpeta
    enc=$(printf '%s' "$d" | sed 's/[^A-Za-z0-9]/-/g')
    cdir="$HOME/.claude/projects/$enc"
    csessions=0; cts=0
    if [ -d "$cdir" ]; then
        newest=$(ls -t "$cdir"/*.jsonl 2>/dev/null | head -1)
        if [ -n "$newest" ]; then
            csessions=$(ls "$cdir"/*.jsonl 2>/dev/null | wc -l)
            cts=$(stat -c %Y "$newest")
        fi
    fi

    last=$(git -C "$d" log -1 --format='%ct	%s' 2>/dev/null | tr -d '\r')
    [ -z "$last" ] && last="0	(sin commits)"
    printf 'REPO\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(basename "$d")" "$d" "$branch" "$changes" "$ahead" "$behind" \
        "$([ -n "$upstream" ] && echo 1 || echo 0)" "$oss" "$csessions" "$cts" "$last"
done
