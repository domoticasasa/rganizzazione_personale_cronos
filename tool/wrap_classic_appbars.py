#!/usr/bin/env python3
"""Wrap Scaffold/classic AppBars with wrapClassicAppBarChrome(context, ...)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"

SKIP_NAMES = {
    "classic_app_bar_chrome.dart",
    "futuristic_topbar.dart",
    "futuristic_inline_toolbar.dart",
    "futuristic_nav_shell.dart",
    "futuristic_page_shell.dart",
    "login_page.dart",
    "change_password_page.dart",
    "change_password_reset_page.dart",
}

APPBAR_RE = re.compile(r"(?<![A-Za-z0-9_])AppBar\s*\(")


def find_matching_paren(s: str, open_idx: int) -> int:
    depth = 0
    i = open_idx
    in_str = None
    while i < len(s):
        c = s[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
            i += 1
            continue
        if c in ("'", '"'):
            in_str = c
            i += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def import_line_for(path: Path) -> str:
    rel = path.relative_to(ROOT).as_posix()
    # lib/pages/foo.dart -> ../widgets
    # lib/pages/home/foo.dart -> ../../widgets
    depth = rel.count("/")
    prefix = "../" * depth
    if rel.startswith("widgets/"):
        return "import 'classic_app_bar_chrome.dart';"
    return f"import '{prefix}widgets/classic_app_bar_chrome.dart';"


def ensure_import(text: str, path: Path) -> str:
    if "classic_app_bar_chrome.dart" in text:
        return text
    imp = import_line_for(path)
    lines = text.splitlines(keepends=True)
    last_imp = -1
    for i, line in enumerate(lines):
        if line.startswith("import "):
            last_imp = i
    if last_imp >= 0:
        lines.insert(last_imp + 1, imp + "\n")
        return "".join(lines)
    return imp + "\n" + text


def wrap_appbars_in_text(text: str) -> str:
    for key in ("appBar:", "classicAppBar:"):
        idx = 0
        while True:
            pos = text.find(key, idx)
            if pos < 0:
                break
            line_start = text.rfind("\n", 0, pos) + 1
            if text[line_start:pos].strip().startswith("//"):
                idx = pos + len(key)
                continue

            window = text[pos : pos + 220]
            m = APPBAR_RE.search(window)
            if not m:
                idx = pos + len(key)
                continue
            app_pos = pos + m.start()
            before = text[max(0, app_pos - 48) : app_pos]
            if "wrapClassicAppBarChrome" in before:
                idx = app_pos + 6
                continue

            open_paren = text.find("(", app_pos)
            close = find_matching_paren(text, open_paren)
            if close < 0:
                idx = app_pos + 6
                continue

            wrapped = (
                "wrapClassicAppBarChrome(context, "
                + text[app_pos : close + 1]
                + ")"
            )
            text = text[:app_pos] + wrapped + text[close + 1 :]
            idx = app_pos + len(wrapped)

    while True:
        m = re.search(
            r"appBar:\s*(?!wrapClassicAppBarChrome)(_buildAppBar\(\))",
            text,
        )
        if not m:
            break
        text = (
            text[: m.start()]
            + "appBar: wrapClassicAppBarChrome(context, "
            + m.group(1)
            + ")"
            + text[m.end() :]
        )
    return text


def main() -> None:
    changed: list[str] = []
    for path in sorted(ROOT.rglob("*.dart")):
        if path.name in SKIP_NAMES:
            continue
        original = path.read_text(encoding="utf-8")
        if "AppBar(" not in original and "_buildAppBar()" not in original:
            continue
        if "appBar:" not in original and "classicAppBar:" not in original:
            continue

        text = wrap_appbars_in_text(original)
        if text == original:
            continue
        text = ensure_import(text, path)
        path.write_text(text, encoding="utf-8")
        changed.append(str(path.relative_to(ROOT.parent)))

    print(f"changed {len(changed)}")
    for f in changed:
        print(f)


if __name__ == "__main__":
    main()
