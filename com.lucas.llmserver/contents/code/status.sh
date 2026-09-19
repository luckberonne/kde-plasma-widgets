#!/bin/sh
# Uso: status.sh [unidad-systemd-de-usuario]
U="${1:-llama-server.service}"
ACTIVE=$(systemctl --user is-active "$U" 2>/dev/null)
echo "ACTIVE=$ACTIVE"
[ "$ACTIVE" = "active" ] || exit 0
PID=$(systemctl --user show -p MainPID --value "$U")
echo "PID=$PID"
echo "MEM=$(systemctl --user show -p MemoryCurrent --value "$U")"
SINCE=$(systemctl --user show -p ActiveEnterTimestamp --value "$U")
[ -n "$SINCE" ] && echo "SINCE=$(date -d "$SINCE" +%s 2>/dev/null)"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null |
        head -1 | awk -F', *' '{print "VRAM_USED=" $1; print "VRAM_TOTAL=" $2}'
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null |
        awk -F', *' -v p="$PID" '$1==p{print "VRAM_PROC=" $2}'
fi
