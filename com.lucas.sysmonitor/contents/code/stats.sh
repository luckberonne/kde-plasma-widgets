#!/bin/sh
# Emite pares CLAVE=VALOR con las metricas del sistema. Pensado para ser
# invocado periodicamente por el widget via el motor "executable" de Plasma.

read -r cpu a b c d e f g h i j < /proc/stat
echo "CPU_RAW=$a $b $c $d $e $f $g $h"

awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "RAM_TOTAL_KB=%d\nRAM_AVAIL_KB=%d\n", t, a}' /proc/meminfo

DISK_PATH="${1:-/}"
df -B1 --output=size,used "$DISK_PATH" 2>/dev/null | tail -1 | awk '{printf "DISK_TOTAL=%d\nDISK_USED=%d\n", $1, $2}'

sensors -u 2>/dev/null | awk '
  /^k10temp|^coretemp/{k=1; g=0; next}
  /^amdgpu/{g=1; k=0; next}
  /^[A-Za-z0-9_.:-]+-/{k=0; g=0}
  k && /temp1_input/{print "CPU_TEMP="$2; k=0}
  g && /^edge:/{inedge=1; next}
  g && inedge && /temp1_input/{print "IGPU_TEMP="$2; inedge=0; g=0}
'

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | \
    awk -F', *' '{printf "GPU_UTIL=%s\nGPU_MEM_USED=%s\nGPU_MEM_TOTAL=%s\nGPU_TEMP=%s\n", $1,$2,$3,$4}'
fi

for c in /sys/class/drm/card*/device; do
  if [ -f "$c/gpu_busy_percent" ] && [ "$(cat "$c/vendor" 2>/dev/null)" = "0x1002" ]; then
    echo "IGPU_UTIL=$(cat "$c/gpu_busy_percent")"
    break
  fi
done
