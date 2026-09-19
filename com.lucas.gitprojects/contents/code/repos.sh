#!/bin/sh
# Uso: repos.sh <carpeta-raíz> [profundidad]
# Imprime una línea REPO por repositorio Git encontrado (campos separados por tabulador).
ROOT="$1"
DEPTH="${2:-3}"
case "$ROOT" in "~"*) ROOT="$HOME${ROOT#\~}" ;; esac
[ -d "$ROOT" ] || { printf 'ERROR\tNo existe la carpeta %s\n' "$ROOT"; exit 0; }

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
    last=$(git -C "$d" log -1 --format='%ct	%s' 2>/dev/null | tr -d '\r')
    [ -z "$last" ] && last="0	(sin commits)"
    printf 'REPO\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(basename "$d")" "$d" "$branch" "$changes" "$ahead" "$behind" "$([ -n "$upstream" ] && echo 1 || echo 0)" "$last"
done
