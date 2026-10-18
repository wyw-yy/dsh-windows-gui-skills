"""pywinauto bridge for the windows-gui-control skill.

Why this exists: PowerShell + UIA can already dump a control tree, but
pywinauto gives a friendlier walker, proper ValuePattern/TextPattern readers
and backend="uia"/"win32" switching. It is the same underlying Windows APIs,
so it sees exactly what UIA sees (nothing more).

Usage (all output is plain text or JSON on stdout):

  python uia.py windows
  python uia.py tree   --title "STM32CubeMX" --depth 4
  python uia.py find   --title "..." --name "GENERATE CODE"
  python uia.py click  --title "..." --name "OK"
  python uia.py click  --title "..." --auto-id 1234
  python uia.py text   --title "..."
  python uia.py focus  --title "..."
  python uia.py value  --title "..." --auto-id 5678

Every command exits 0 on success, 2 when the window/control is not found,
1 on an unexpected error (message on stderr).
"""

import argparse
import json
import sys

try:
    from pywinauto import Desktop
except Exception as exc:  # pragma: no cover
    sys.stderr.write("pywinauto import failed: %s\n" % exc)
    sys.exit(1)

# Windows console defaults to GBK here; window titles contain CJK and zero-width
# spaces, which crash print(). Force UTF-8 with replacement.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def iter_windows():
    for w in Desktop(backend="uia").windows():
        try:
            rect = w.rectangle()
            yield {
                "title": w.window_text(),
                "pid": w.process_id(),
                "handle": w.handle,
                "class": w.class_name(),
                "rect": [rect.left, rect.top, rect.right, rect.bottom],
                "visible": w.is_visible(),
            }
        except Exception:
            continue


def find_window(title=None, handle=None):
    desktop = Desktop(backend="uia")
    if handle:
        return desktop.window(handle=handle)
    if not title:
        raise SystemExit("need --title or --handle")
    # exact title first, then substring
    try:
        w = desktop.window(title=title)
        if w.exists(timeout=0.3):
            return w
    except Exception:
        pass
    for w in desktop.windows():
        try:
            if title.lower() in (w.window_text() or "").lower():
                return w
        except Exception:
            continue
    return None


def control_of(w, name=None, auto_id=None, control_type=None):
    crit = {}
    if name:
        crit["title"] = name
    if auto_id:
        crit["auto_id"] = auto_id
    if control_type:
        crit["control_type"] = control_type
    if not crit:
        raise SystemExit("need --name / --auto-id / --type")
    return w.child_window(**crit)


def cmd_windows(_a):
    for info in iter_windows():
        if info["title"]:
            print("%-9s pid=%-6s %-22s %s" % (info["handle"], info["pid"], info["class"][:22], info["title"]))


def cmd_tree(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("NOT FOUND", file=sys.stderr)
        return 2
    w.set_focus()
    for c in w.descendants(depth=a.depth):
        try:
            r = c.rectangle()
            print(
                "%s%s | id=%s | %s [%d,%d]"
                % (
                    "  " * 0,
                    c.friendly_class_name(),
                    c.element_info.automation_id or "-",
                    (c.window_text() or "")[:60].replace("\n", " "),
                    (r.left + r.right) // 2,
                    (r.top + r.bottom) // 2,
                )
            )
        except Exception:
            continue
    return 0


def cmd_find(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("WINDOW NOT FOUND", file=sys.stderr)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if not c.exists(timeout=a.timeout):
        print("CONTROL NOT FOUND", file=sys.stderr)
        return 2
    r = c.rectangle()
    print(json.dumps({
        "class": c.friendly_class_name(),
        "text": c.window_text(),
        "auto_id": c.element_info.automation_id,
        "rect": [r.left, r.top, r.right, r.bottom],
        "center": [(r.left + r.right) // 2, (r.top + r.bottom) // 2],
        "enabled": c.is_enabled(),
    }, ensure_ascii=False))
    return 0


def cmd_click(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("WINDOW NOT FOUND", file=sys.stderr)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if not c.exists(timeout=a.timeout):
        print("CONTROL NOT FOUND", file=sys.stderr)
        return 2
    c.click_input()
    print("CLICKED")
    return 0


def cmd_text(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("WINDOW NOT FOUND", file=sys.stderr)
        return 2
    seen = []
    for c in w.descendants(depth=a.depth):
        try:
            t = (c.window_text() or "").strip()
        except Exception:
            continue
        if t and t not in seen:
            seen.append(t)
    for t in seen:
        print(t.replace("\n", " | ")[:160])
    return 0


def cmd_value(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("WINDOW NOT FOUND", file=sys.stderr)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if not c.exists(timeout=a.timeout):
        print("CONTROL NOT FOUND", file=sys.stderr)
        return 2
    try:
        print(c.get_value())
        return 0
    except Exception:
        try:
            print(c.window_text())
            return 0
        except Exception as exc:
            print("NO VALUE: %s" % exc, file=sys.stderr)
            return 1


def cmd_focus(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print("WINDOW NOT FOUND", file=sys.stderr)
        return 2
    w.set_focus()
    print("FOCUSED")
    return 0


def main():
    p = argparse.ArgumentParser(description="pywinauto bridge (uia backend)")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--title")
        sp.add_argument("--handle", type=int)
        sp.add_argument("--timeout", type=float, default=2.0)

    common(sub.add_parser("windows"))
    sp = sub.add_parser("tree"); common(sp); sp.add_argument("--depth", type=int, default=4)
    sp = sub.add_parser("find"); common(sp); sp.add_argument("--name"); sp.add_argument("--auto-id"); sp.add_argument("--type")
    sp = sub.add_parser("click"); common(sp); sp.add_argument("--name"); sp.add_argument("--auto-id"); sp.add_argument("--type")
    sp = sub.add_parser("text"); common(sp); sp.add_argument("--depth", type=int, default=4)
    sp = sub.add_parser("value"); common(sp); sp.add_argument("--name"); sp.add_argument("--auto-id"); sp.add_argument("--type")
    common(sub.add_parser("focus"))

    a = p.parse_args()
    fn = {
        "windows": cmd_windows, "tree": cmd_tree, "find": cmd_find, "click": cmd_click,
        "text": cmd_text, "value": cmd_value, "focus": cmd_focus,
    }[a.cmd]
    try:
        return fn(a)
    except SystemExit:
        raise
    except Exception as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
