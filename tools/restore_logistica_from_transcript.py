#!/usr/bin/env python3
"""Ripristina file logistica dall'ultimo Write nei transcript Cursor."""
import json
import os
import re
from pathlib import Path

# nome file -> percorso destinazione (match esatto sul path nel transcript)
TARGETS = {
    r"lib\pages\admin_logistica_multicard_page.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\pages\admin_logistica_multicard_page.dart"
    ),
    r"lib\pages\logistica_rcc_carburante_page.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\pages\logistica_rcc_carburante_page.dart"
    ),
    r"lib\pages\logistica_rcc_mdo_carburante_page.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\pages\logistica_rcc_mdo_carburante_page.dart"
    ),
    r"lib\utils\rcc_mod04_excel.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\utils\rcc_mod04_excel.dart"
    ),
    r"lib\utils\rcc_mdo_excel.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\utils\rcc_mdo_excel.dart"
    ),
    r"lib\widgets\data_cell_audit_hover.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\widgets\data_cell_audit_hover.dart"
    ),
    r"lib\utils\field_timestamps.dart": Path(
        r"c:\flutter_projects\organizzazione_personale_cronos - mod\lib\utils\field_timestamps.dart"
    ),
}

TRANSCRIPT_ROOT = Path(
    r"C:\Users\alexandru.cibuc\.cursor\projects\c-flutter-projects-organizzazione-personale-cronos-mod\agent-transcripts"
)


def extract_from_tool_input(inp: dict, path_suffix: str) -> str | None:
    path = str(inp.get("path", "")).replace("/", "\\")
    suffix = path_suffix.replace("/", "\\")
    if not path.endswith(suffix):
        return None
    if "contents" in inp:
        c = inp["contents"]
        if not _content_matches_target(suffix, c):
            return None
        return c
    return None


def _content_matches_target(suffix: str, content: str) -> bool:
    """Evita di salvare una pagina intera al posto di un file utils."""
    if "class LogisticaRcc" in content or "class AdminLogisticaMulticard" in content:
        return suffix.endswith("_page.dart")
    if suffix.endswith("field_timestamps.dart"):
        return "mergeFieldTimestampActorUuids" in content or "fieldInsertedAtLabel" in content
    if suffix.endswith("rcc_mdo_excel.dart"):
        return "buildRccMdoExcelBytes" in content and "class LogisticaRcc" not in content
    if suffix.endswith("rcc_mod04_excel.dart"):
        return "buildRccMod04ExcelBytes" in content
    if suffix.endswith("data_cell_audit_hover.dart"):
        return "decorateDataCellWithAuditHover" in content
    return True


def extract_from_patch(text: str, path_suffix: str) -> str | None:
    suffix = path_suffix.replace("/", "\\")
    if suffix not in text or "Add File" not in text:
        return None
  # patch after filename line
    idx = text.find(suffix)
    if idx < 0:
        return None
    chunk = text[idx:]
    lines = chunk.split("\n")
    out: list[str] = []
    started = False
    for ln in lines:
        if not started:
            if ln.startswith("+") and "import" in ln:
                started = True
                out.append(ln[1:])
            continue
        if ln.startswith("***"):
            break
        if ln.startswith("+"):
            out.append(ln[1:])
        elif ln.startswith(" ") and started:
            out.append(ln[1:])
    body = "\n".join(out).strip()
    if len(body) <= 500:
        return None
    if not _content_matches_target(suffix, body):
        return None
    return body


def extract_from_line(line: str, path_suffix: str) -> str | None:
    if path_suffix.replace("/", "\\") not in line.replace("/", "\\"):
        return None
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        return None
    msg = obj.get("message", {})
    content = msg.get("content", [])
    if isinstance(content, str):
        return None
    for part in content:
        if part.get("type") != "tool_use":
            continue
        inp = part.get("input")
        if isinstance(inp, dict):
            c = extract_from_tool_input(inp, path_suffix)
            if c:
                return c
            patch = inp.get("patch") or inp.get("input")
            if isinstance(patch, str):
                c = extract_from_patch(patch, path_suffix)
                if c:
                    return c
        elif isinstance(inp, str):
            c = extract_from_patch(inp, path_suffix)
            if c:
                return c
    return None


def main() -> None:
    found: dict[str, str] = {}
    for fp in TRANSCRIPT_ROOT.rglob("*.jsonl"):
        try:
            text = fp.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for line in text.splitlines():
            for suffix in TARGETS:
                c = extract_from_line(line, suffix)
                if c and len(c) > len(found.get(suffix, "")):
                    found[suffix] = c

    for suffix, dest in TARGETS.items():
        content = found.get(suffix)
        if not content:
            print(f"MISSING {suffix}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8", newline="\n")
        print(f"WROTE {suffix} ({len(content)} chars) -> {dest}")


if __name__ == "__main__":
    main()
