#!/bin/sh
# Emite el estado de audio: SINKS/SOURCES en JSON (una línea) y los predeterminados.
echo "DSINK=$(pactl get-default-sink 2>/dev/null)"
echo "DSOURCE=$(pactl get-default-source 2>/dev/null)"
echo "SINKS=$(pactl -f json list sinks 2>/dev/null | tr -d '\n')"
echo "SOURCES=$(pactl -f json list sources 2>/dev/null | tr -d '\n')"
