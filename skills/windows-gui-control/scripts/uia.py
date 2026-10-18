"""pywinauto bridge for the windows-gui-control skill.

Why this exists: pywinauto gives a friendlier tree walker than raw UIA COM and
handy TextPattern/ValuePattern readers, with backend="uia"/"win32" switching.
It is the same Windows APIs underneath, so it sees exactly what UIA sees and
nothing more (no pixels, no Java/SWT internals).

Usage (stdout is text, or JSON for find/click/value):

  python uia.py windows
  python uia.py tree   --title "STM32CubeMX" --depth 4
  python uia.py find   --title "..." --name "GENERATE CODE"
  python uia.py click  --title "..." --name "OK"          # semantic click (Invoke/Select/Toggle)
  python uia.py click  --title "..." --auto-id 1234 --input  # physical click, refuses if not foreground
  python uia.py text   --title "..."
  python uia.py focus  --title "..."
  python uia.py value  --title "..." --auto-id 5678

Exit codes: 0 ok, 2 window/control not found, 3 refused (unsafe physical click),
1 unexpected error (message on stderr).

Two rules this script enforces, because breaking them cost real damage:
  * a semantic click never moves the mouse, so it cannot hit whatever window is
    on top;
  * a physical click is refused unless the target window is already foreground,
    because click_input() posts at absolute screen coordinates.
"""

import argparse
import ctypes
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


def make_dpi_aware():
    """UIA hands out PHYSICAL pixels; GetSystemMetrics on a DPI-unaware process
    returns scaled ones. Without this a 2560x1600 screen at 150% reports 1707
    wide, so every window past x=1707 looks 'off-screen'."""
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
        return
    except Exception:
        pass
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass


def is_foreground(handle):
    try:
        return int(handle) == int(ctypes.windll.user32.GetForegroundWindow())
    except Exception:
        return False


def is_minimized(handle):
    try:
        return bool(ctypes.windll.user32.IsIconic(int(handle)))
    except Exception:
        return False


def rect_bogus(r):
    """True when a rectangle cannot describe a clickable on-screen control:
    collapsed to nothing (the classic signature of a minimized window, whose
    rect degenerates to 158x26 at -32000) or entirely outside the virtual screen."""
    try:
        w = int(r.right) - int(r.left)
        h = int(r.bottom) - int(r.top)
        if w <= 4 or h <= 4:
            return True
        u = ctypes.windll.user32
        vx, vy = u.GetSystemMetrics(76), u.GetSystemMetrics(77)
        vw, vh = u.GetSystemMetrics(78), u.GetSystemMetrics(79)
        if vw <= 0 or vh <= 0:
            vw, vh = u.GetSystemMetrics(0), u.GetSystemMetrics(1)
        if int(r.right) <= vx or int(r.bottom) <= vy:
            return True
        if int(r.left) >= vx + vw or int(r.top) >= vy + vh:
            return True
        return False
    except Exception:
        return False


def bogus_reason(handle, c=None):
    """Return None if the target is sane, else a short human-readable reason."""
    if is_minimized(handle):
        return "window is minimized (IsIconic); its coordinates do not exist - call focus/SW_RESTORE first"
    try:
        r = c.rectangle() if c is not None else None
        if r is not None and rect_bogus(r):
            return "control rectangle is degenerate/off-screen (%d,%d)-(%d,%d); usually a minimized or hidden parent" % (
                r.left, r.top, r.right, r.bottom)
    except Exception:
        pass
    return None


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
    """Return a resolved wrapper (never a WindowSpecification).

    pywinauto's Desktop().window(...) returns a *spec*; only after .exists() /
    .wrapper_object() do you get a wrapper with .children(), .descendants() and
    .handle. Mixing the two is what made every control lookup fail before.
    """
    desktop = Desktop(backend="uia")
    if handle:
        spec = desktop.window(handle=handle)
        return spec.wrapper_object() if spec.exists(timeout=1.0) else None
    if not title:
        raise SystemExit("need --title or --handle")
    exact = desktop.window(title=title)
    if exact.exists(timeout=0.3):
        return exact.wrapper_object()
    # Desktop().windows() can hand back ElementInfo objects, which have no
    # .descendants(); blindly calling .wrapper_object() inside the match loop
    # made every lookup return None (the AttributeError was swallowed here).
    for w in desktop.windows():
        try:
            text = w.window_text() or ""
        except Exception:
            continue
        if title.lower() not in text.lower():
            continue
        if hasattr(w, "descendants"):
            return w
        try:
            return w.wrapper_object()
        except Exception:
            continue
    return None


def print_not_found(title=None, handle=None):
    print("WINDOW NOT FOUND (%s)" % (handle or title), file=sys.stderr)
    try:
        names = []
        for w in Desktop(backend="uia").windows():
            try:
                names.append((w.window_text() or "").strip())
            except Exception:
                continue
        names = [n for n in names if n][:12]
        if names:
            print("available windows:", file=sys.stderr)
            for n in names:
                print("  - %s" % n, file=sys.stderr)
    except Exception:
        pass


def depth_of(el):
    """Walk element_info.parent up to the desktop to get a real nesting depth."""
    depth = 0
    try:
        node = el.element_info
        while node is not None and depth < 40:
            node = getattr(node, "parent", None)
            if node is None:
                break
            depth += 1
    except Exception:
        return 0
    return max(depth - 1, 0)


def match(el, name=None, auto_id=None, control_type=None):
    try:
        if control_type and (el.element_info.control_type or "") != control_type:
            return False
        if name is not None and (el.window_text() or "") != name:
            return False
        if auto_id is not None and (el.element_info.automation_id or "") != auto_id:
            return False
    except Exception:
        return False
    return True


def control_of(w, name=None, auto_id=None, control_type=None):
    """Find one control inside a wrapper. Works on the wrapper itself too."""
    if not (name or auto_id or control_type):
        raise SystemExit("need --name / --auto-id / --type")
    if match(w, name, auto_id, control_type):
        return w
    try:
        for c in w.descendants():
            if match(c, name, auto_id, control_type):
                return c
    except Exception:
        pass
    return None


def describe(c):
    r = c.rectangle()
    try:
        patterns = [p for p in ("invoke", "select", "toggle", "set_edit_text")
                    if hasattr(c, p)]
    except Exception:
        patterns = []
    return {
        "class": c.friendly_class_name(),
        "control_type": c.element_info.control_type,
        "text": c.window_text(),
        "auto_id": c.element_info.automation_id,
        "rect": [r.left, r.top, r.right, r.bottom],
        "center": [(r.left + r.right) // 2, (r.top + r.bottom) // 2],
        "enabled": c.is_enabled(),
        "patterns": patterns,
    }


def semantic_click(c):
    errors = []
    for name in ("invoke", "select", "toggle"):
        try:
            getattr(c, name)()
            return name
        except Exception as exc:
            errors.append("%s:%s" % (name, exc.__class__.__name__))
    raise RuntimeError("no semantic click pattern worked (%s)" % ", ".join(errors))


def cmd_windows(_a):
    for info in iter_windows():
        if info["title"]:
            print("%-9s pid=%-6s %-22s %s" % (info["handle"], info["pid"], info["class"][:22], info["title"]))
    return 0


def cmd_tree(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print_not_found(a.title, a.handle)
        return 2
    # Do not steal focus by default: dumping a tree should be an observation.
    if getattr(a, "focus", False):
        try:
            w.set_focus()
        except Exception:
            pass
    for c in w.descendants(depth=a.depth):
        try:
            d = depth_of(c)
            r = c.rectangle()
            print(
                "%s%s | id=%s | %s [%d,%d]"
                % (
                    "  " * d,
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
        print_not_found(a.title, a.handle)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if c is None:
        print("CONTROL NOT FOUND", file=sys.stderr)
        return 2
    info = describe(c)
    reason = bogus_reason(w.handle, c)
    if reason:
        info["found"] = True
        info["unusable"] = reason
        print(json.dumps(info, ensure_ascii=False))
        return 4
    print(json.dumps(info, ensure_ascii=False))
    return 0


def cmd_click(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print_not_found(a.title, a.handle)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if c is None:
        print("CONTROL NOT FOUND", file=sys.stderr)
        return 2

    reason = bogus_reason(w.handle, c)
    if reason and not a.force:
        print(json.dumps({
            "clicked": False,
            "refused": reason,
            "hint": "restore the window first (`python uia.py focus`, or SW_RESTORE); --force overrides this guard",
        }, ensure_ascii=False))
        return 4

    if a.input:
        fg_before = is_foreground(w.handle)
        if not fg_before and not a.force:
            print(json.dumps({
                "clicked": False,
                "refused": "target window is not foreground; a physical click would land on whatever is on top",
                "hint": "call `python uia.py focus`, re-check occlusion, or pass --force knowingly",
                "foreground_before": False,
            }, ensure_ascii=False))
            return 3
        try:
            w.set_focus()
        except Exception:
            pass
        c.click_input()
        print(json.dumps({"clicked": True, "method": "click_input",
                          "foreground_before": fg_before,
                          "foreground_after": is_foreground(w.handle)},
                         ensure_ascii=False))
        return 0

    method = semantic_click(c)
    print(json.dumps({"clicked": True, "method": method}, ensure_ascii=False))
    return 0


def cmd_text(a):
    w = find_window(a.title, a.handle)
    if w is None:
        print_not_found(a.title, a.handle)
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
        print_not_found(a.title, a.handle)
        return 2
    c = control_of(w, a.name, a.auto_id, a.type)
    if c is None:
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
        print_not_found(a.title, a.handle)
        return 2
    w.set_focus()
    print("FOCUSED")
    return 0


def main():
    make_dpi_aware()
    p = argparse.ArgumentParser(description="pywinauto bridge (uia backend)")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--title")
        sp.add_argument("--handle", type=int)
        sp.add_argument("--timeout", type=float, default=2.0)

    def target(sp):
        sp.add_argument("--name")
        sp.add_argument("--auto-id")
        sp.add_argument("--type")

    common(sub.add_parser("windows"))
    sp = sub.add_parser("tree"); common(sp); sp.add_argument("--depth", type=int, default=4)
    sp.add_argument("--focus", action="store_true", help="bring the window to the foreground first (observation should not steal focus)")
    sp = sub.add_parser("find"); common(sp); target(sp)
    sp = sub.add_parser("click"); common(sp); target(sp)
    sp.add_argument("--input", action="store_true", help="physical click instead of Invoke/Select/Toggle")
    sp.add_argument("--force", action="store_true", help="allow a physical click even if the window is not foreground")
    sp = sub.add_parser("text"); common(sp); sp.add_argument("--depth", type=int, default=4)
    sp = sub.add_parser("value"); common(sp); target(sp)
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
