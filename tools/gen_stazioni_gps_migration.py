#!/usr/bin/env python3
"""Generate SQL migration: stazioni GPS from RFI CSV gist."""
from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "deploy" / "stazioni_italiane.csv"
OUT = ROOT / "supabase" / "migrations" / "20260802160000_stazioni_gps_from_csv.sql"


def esc(s: str) -> str:
    return s.replace("'", "''")


def main() -> None:
    rows = list(csv.DictReader(SRC.open(encoding="utf-8")))
    vals: list[tuple[str, str, float, float]] = []
    for r in rows:
        nome = (r.get("long_name") or "").strip()
        code = (r.get("code") or "").strip()
        try:
            lat = float(r["latitude"])
            lon = float(r["longitude"])
        except Exception:
            continue
        if not nome or abs(lat) > 90 or abs(lon) > 180:
            continue
        vals.append((nome, code, lat, lon))

    seen: set[str] = set()
    unique: list[tuple[str, str, float, float]] = []
    for nome, code, lat, lon in vals:
        key = nome.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append((nome, code, lat, lon))

    chunks: list[str] = []
    for i in range(0, len(unique), 400):
        part = unique[i : i + 400]
        lines = ",\n".join(
            f"    ('{esc(n)}', '{esc(c)}', {lat}, {lon})"
            for n, c, lat, lon in part
        )
        chunks.append(lines)

    parts: list[str] = []
    parts.append(
        """-- GPS stazioni italiane da CSV RFI (gist MarcoBuster).
-- Aggiorna coordinate mancanti e inserisce stazioni assenti.

alter table public.stazioni
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision,
  add column if not exists codice_rfi text;

create index if not exists stazioni_codice_rfi_idx
  on public.stazioni (codice_rfi)
  where codice_rfi is not null;

create temporary table _stazioni_csv_seed (
  nome text not null,
  codice_rfi text,
  latitudine double precision not null,
  longitudine double precision not null
);
"""
    )

    for lines in chunks:
        parts.append(
            "INSERT INTO _stazioni_csv_seed "
            "(nome, codice_rfi, latitudine, longitudine) VALUES\n"
            f"{lines};\n"
        )

    parts.append(
        """
UPDATE public.stazioni s
SET
  latitudine = COALESCE(s.latitudine, t.latitudine),
  longitudine = COALESCE(s.longitudine, t.longitudine),
  codice_rfi = COALESCE(NULLIF(trim(s.codice_rfi), ''), t.codice_rfi)
FROM _stazioni_csv_seed t
WHERE lower(trim(s.nome)) = lower(trim(t.nome));

INSERT INTO public.stazioni (nome, attiva, latitudine, longitudine, codice_rfi)
SELECT t.nome, true, t.latitudine, t.longitudine, t.codice_rfi
FROM _stazioni_csv_seed t
WHERE NOT EXISTS (
  SELECT 1 FROM public.stazioni s
  WHERE lower(trim(s.nome)) = lower(trim(t.nome))
);

DROP TABLE IF EXISTS _stazioni_csv_seed;
"""
    )

    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"wrote {OUT} stations={len(unique)} bytes={OUT.stat().st_size}")


if __name__ == "__main__":
    main()
