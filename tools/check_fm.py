"""Check SKILL.md frontmatter for every skill in a folder.

  python tools/check_fm.py                       # installed skills
  python tools/check_fm.py --root <pkg>          # the shipped package (skills/ inside)
  python tools/check_fm.py --root <dir> --quiet  # exit code only

Why --root exists: the old version only ever looked at %USERPROFILE%/<.agents>/skills,
so a broken frontmatter could ship unnoticed. Point it at the package before you
publish and the same check runs against what users will actually download.

Exit code: 0 all good, 1 at least one skill failed.
"""
import argparse
import io
import os
import sys

try:
    import yaml
except ImportError:  # keep the check usable without PyYAML
    yaml = None


def skill_dirs(root):
    """Yield (name, SKILL.md path). Accepts either a skills/ parent or the folder itself."""
    inner = os.path.join(root, "skills")
    base = inner if os.path.isdir(inner) else root
    for name in sorted(os.listdir(base)):
        p = os.path.join(base, name, "SKILL.md")
        if os.path.isfile(p):
            yield name, p


def parse_frontmatter(text):
    if not text.startswith("---"):
        raise ValueError("no frontmatter")
    end = text.find("\n---", 3)
    if end < 0:
        raise ValueError("frontmatter not closed")
    block = text[3:end]
    if yaml is None:
        # Minimal fallback: top-level "key:" lines only.
        keys = [ln.split(":", 1)[0].strip() for ln in block.splitlines()
                if ln.strip() and not ln.startswith((" ", "\t")) and ":" in ln]
        if "name" not in keys or "description" not in keys:
            raise ValueError("missing name/description (PyYAML not installed)")
        return keys
    data = yaml.safe_load(block)
    if not isinstance(data, dict):
        raise ValueError("frontmatter is not a mapping")
    for k in ("name", "description"):
        if k not in data:
            raise ValueError("missing " + k)
    return sorted(data)


def main():
    ap = argparse.ArgumentParser()
    default = os.path.join(os.environ.get("USERPROFILE", "."), ".agents", "skills")
    ap.add_argument("--root", default=default, help="skill folder, or a package with skills/ inside")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    if not os.path.isdir(a.root):
        print("not a directory: " + a.root)
        return 1

    bad = 0
    n = 0
    for name, path in skill_dirs(a.root):
        n += 1
        try:
            with io.open(path, encoding="utf-8") as fh:
                keys = parse_frontmatter(fh.read())
            if not a.quiet:
                print("  %-28s OK   keys=%s" % (name, keys))
        except Exception as exc:
            bad += 1
            print("  %-28s FAIL %s" % (name, str(exc).splitlines()[0]))
    if n == 0:
        print("no SKILL.md found under " + a.root)
        return 1
    if not a.quiet:
        print("%d skills, %d failed" % (n, bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
