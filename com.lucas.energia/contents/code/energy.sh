#!/bin/sh
# Lee la batería (sysfs) y el perfil de energía activo (power-profiles-daemon).
BAT=""
for b in /sys/class/power_supply/BAT*; do [ -d "$b" ] && BAT="$b" && break; done
if [ -n "$BAT" ]; then
    echo "HAS_BAT=1"
    for k in capacity status power_now current_now voltage_now energy_now energy_full energy_full_design charge_now charge_full charge_full_design cycle_count; do
        [ -r "$BAT/$k" ] && echo "$k=$(cat "$BAT/$k")"
    done
else
    echo "HAS_BAT=0"
fi
AC=0
for a in /sys/class/power_supply/A*; do
    [ -r "$a/online" ] && [ "$(cat "$a/online")" = "1" ] && AC=1
done
echo "AC=$AC"
if command -v powerprofilesctl >/dev/null 2>&1; then
    echo "PROFILE=$(powerprofilesctl get 2>/dev/null)"
    echo "PROFILES=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[ *]*\(performance\|balanced\|power-saver\):.*/\1/p' | tr '\n' ',')"
fi
