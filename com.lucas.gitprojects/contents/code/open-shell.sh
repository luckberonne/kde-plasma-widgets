#!/bin/sh
# Uso: open-shell.sh <comando>
# Ejecuta <comando> en fish si está instalado; si no, en el shell por
# defecto del usuario ($SHELL). Al terminar el comando deja el shell
# abierto (como hacía "fish -C").
CMD="$1"
SH="$(command -v fish || echo "$SHELL")"
exec "$SH" -c "$CMD; exec \"$SH\""
