#!/bin/sh
# Pasa a usar automáticamente los dispositivos de audio nuevos (auriculares, USB, Bluetooth).
# Escucha los eventos de PipeWire/PulseAudio; ignora HDMI y monitores.

desc() { # tipo (sinks|sources) nombre
    pactl list "$1" | awk -v n="$2" '$1=="Name:"{m=($2==n)} m&&/Description:/{sub(/^[ \t]*Description: /,"");print;exit}'
}

list() { # tipo -> nombres elegibles
    pactl list short "$1" | cut -f2 | grep -v -e '\.monitor$' -e HDMI
}

known_sinks=$(list sinks)
known_sources=$(list sources)

check() {
    changed=0
    for n in $(list sinks); do
        echo "$known_sinks" | grep -qxF "$n" && continue
        pactl set-default-sink "$n"; changed=1
    done
    for n in $(list sources); do
        echo "$known_sources" | grep -qxF "$n" && continue
        pactl set-default-source "$n"; changed=1
    done
    known_sinks=$(list sinks)
    known_sources=$(list sources)
    if [ "$changed" = 1 ]; then
        out=$(desc sinks "$(pactl get-default-sink)")
        inp=$(desc sources "$(pactl get-default-source)")
        notify-send -a Audio -i audio-headset "Se está usando" "Salida: $out
Entrada: $inp"
    fi
}

pactl subscribe | while read -r ev; do
    case "$ev" in
        *"'new' on sink "*|*"'new' on source "*|*"'remove' on sink "*|*"'remove' on source "*)
            sleep 1   # deja que el dispositivo termine de registrarse
            check ;;
    esac
done
