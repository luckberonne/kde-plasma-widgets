#!/bin/sh
# Uso: net.sh [interfaz]  (vacío = interfaz de la ruta por defecto)
IFACE="$1"
[ -z "$IFACE" ] && IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && { echo "IFACE="; exit 0; }
awk -v ifc="$IFACE" -F'[: ]+' '$0 ~ ifc":" {
    for(i=1;i<=NF;i++) if($i==ifc){ print "RX=" $(i+1); print "TX=" $(i+9) }
}' /proc/net/dev
echo "IFACE=$IFACE"
