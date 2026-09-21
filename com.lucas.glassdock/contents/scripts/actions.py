#!/usr/bin/env python3
"""Lista las acciones (Actions=) de un .desktop como JSON.

Uso: actions.py <id o ruta>   ->  [{"name","icon","exec"}, ...]
El Exec sale con los códigos de campo (%u, %F...) ya quitados.
"""
import configparser, json, os, re, sys

def dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    sysd = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    extra = ["/var/lib/flatpak/exports/share", os.path.expanduser("~/.local/share/flatpak/exports/share")]
    return [home] + sysd + extra

def find(ident):
    if ident.startswith("/") and os.path.exists(ident):
        return ident
    ident = ident if ident.endswith(".desktop") else ident + ".desktop"
    for d in dirs():
        p = os.path.join(d, "applications", ident)
        if os.path.exists(p):
            return p
    return None

def localized(sec, key, langs):
    for l in langs:
        v = sec.get(f"{key}[{l}]")
        if v:
            return v
    return sec.get(key, "")

def main():
    path = find(sys.argv[1]) if len(sys.argv) > 1 else None
    if not path:
        print("[]"); return
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(path, encoding="utf-8")
    if "Desktop Entry" not in cp:
        print("[]"); return
    lang = (os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "").split(".")[0]
    langs = [lang, lang.split("_")[0]] if lang else []
    out = []
    for aid in cp["Desktop Entry"].get("Actions", "").split(";"):
        sec = f"Desktop Action {aid}"
        if not aid or sec not in cp:
            continue
        s = cp[sec]
        cmd = re.sub(r"%[a-zA-Z%]", lambda m: "%" if m.group(0) == "%%" else "", s.get("Exec", "")).strip()
        if cmd:
            out.append({"name": localized(s, "Name", langs), "icon": s.get("Icon", ""), "exec": cmd})
    print(json.dumps(out, ensure_ascii=False))

main()
