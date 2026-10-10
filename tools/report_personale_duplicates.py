import re
import unicodedata
from collections import defaultdict

import requests

SUPABASE_URL = "https://bjdimalvbdablzoctrsf.supabase.co"
ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqZGltYWx2YmRhYmx6b2N0cnNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5MzczNTcsImV4cCI6MjA4NzUxMzM1N30."
    "Lm4GHd1CWdSMMI87Wx2eBrHcmqFtMXO31hO7Q3BsYyc"
)


def norm_name(value: str) -> str:
    x = (value or "").strip().lower().replace("’", "'")
    x = "".join(c for c in unicodedata.normalize("NFD", x) if unicodedata.category(c) != "Mn")
    x = re.sub(r"[^a-z0-9 ]+", " ", x)
    x = re.sub(r"\s+", " ", x).strip()
    return x


def token_key(value: str) -> str:
    parts = [p for p in norm_name(value).split(" ") if p]
    parts.sort()
    return " ".join(parts)


def main() -> None:
    headers = {"apikey": ANON_KEY, "Authorization": f"Bearer {ANON_KEY}"}
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/personale?select=id,id_uuid,full_name,user_id,email,active&limit=5000",
        headers=headers,
        timeout=30,
    )
    r.raise_for_status()
    rows = r.json()
    print("total personale rows:", len(rows))

    by_exact = defaultdict(list)
    by_token = defaultdict(list)
    for row in rows:
        full_name = (row.get("full_name") or "").strip()
        by_exact[full_name.lower()].append(row)
        tk = token_key(full_name)
        if tk:
            by_token[tk].append(row)

    exact_groups = [g for g in by_exact.values() if len(g) > 1]
    token_groups = [g for g in by_token.values() if len(g) > 1]

    print("exact duplicate groups:", len(exact_groups))
    print("exact duplicate rows:", sum(len(g) for g in exact_groups))
    print("token duplicate groups:", len(token_groups))
    print("token duplicate rows:", sum(len(g) for g in token_groups))

    token_groups.sort(key=lambda g: (-len(g), (g[0].get("full_name") or "")))
    print("top duplicate groups:")
    for g in token_groups[:60]:
        names = " || ".join((x.get("full_name") or "").strip() for x in g)
        print(f"- {len(g)}x: {names}")
        for row in g:
            print(
                "   ->",
                (row.get("full_name") or "").strip(),
                "| email:",
                row.get("email"),
                "| user_id:",
                row.get("user_id"),
            )


if __name__ == "__main__":
    main()

