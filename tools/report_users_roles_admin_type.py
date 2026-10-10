from collections import Counter

import requests

SUPABASE_URL = "https://bjdimalvbdablzoctrsf.supabase.co"
ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqZGltYWx2YmRhYmx6b2N0cnNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5MzczNTcsImV4cCI6MjA4NzUxMzM1N30."
    "Lm4GHd1CWdSMMI87Wx2eBrHcmqFtMXO31hO7Q3BsYyc"
)


def main() -> None:
    h = {"apikey": ANON_KEY, "Authorization": f"Bearer {ANON_KEY}"}
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/users?select=id,username,role,admin_type,full_name,active&limit=5000",
        headers=h,
        timeout=30,
    )
    r.raise_for_status()
    rows = r.json()
    print("users rows:", len(rows))

    role_count = Counter((x.get("role") or "NULL") for x in rows)
    admin_type_count = Counter(str(x.get("admin_type")) for x in rows)
    print("role_count:", dict(role_count))
    print("admin_type_count:", dict(admin_type_count))

    admins = [x for x in rows if (x.get("role") or "").startswith("admin")]
    print("admins sample:", [(a.get("full_name"), a.get("role"), a.get("admin_type")) for a in admins[:40]])


if __name__ == "__main__":
    main()

