#!/usr/bin/env python3
"""Cross-checks every published php-src security advisory against the patches applied to each EOL branch.

php-src advisories (https://github.com/php/php-src/security/advisories) only list the supported branches, so an
advisory published after the last upstream release of an EOL branch is "to triage" for that branch until either:
  - one of its identifiers (GHSA / CVE) appears in the applied patches or in the Sury changelog -> covered
  - patches/<version>/triage has a line "<GHSA-id> <status>: <reason>" (status: not-affected, wontfix, pending)

Writes data/php-src-advisories.json (advisory cache) and data/coverage.json (read by tools/security-report.py).
Exit code 1 when an advisory is untriaged, so CI can flag it.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADVISORIES = ROOT / "data" / "php-src-advisories.json"
COVERAGE = ROOT / "data" / "coverage.json"
TRIAGE_RE = re.compile(r"^(GHSA(?:-[0-9a-z]{4}){3})\s+(not-affected|wontfix|pending)\s*:\s*(.+)$")


def fetch_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "mammoth-lts"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r), r.headers.get("Link", "")


def fetch_advisories():
    url, out = "https://api.github.com/repos/php/php-src/security-advisories?state=published&per_page=100", []
    while url:
        page, link = fetch_json(url)
        out += page
        m = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = m and m[1]
    keep = []
    for a in out:
        cvss = a.get("cvss_severities") or {}
        score = next((c.get("score") for c in (cvss.get("cvss_v4") or {}, cvss.get("cvss_v3") or {}) if c.get("score")), None)
        keep.append({
            "ghsa": a["ghsa_id"],
            "cve": a.get("cve_id"),
            "summary": a.get("summary", "").strip(),
            "published": (a.get("published_at") or "")[:10],
            "severity": (a.get("severity") or "").upper() or None,
            "score": score,
            "patched": sorted({p for v in a.get("vulnerabilities") or [] for p in (v.get("patched_versions") or "").split(",") if p.strip()}),
        })
    return sorted(keep, key=lambda a: a["published"])


def release_date(version):
    data, _ = fetch_json(f"https://www.php.net/releases/index.php?json&version={version}")
    m = re.search(r"(\d{1,2}) (\w{3}) (\d{4})", data.get("date", ""))
    months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    return f"{m[3]}-{months.index(m[2]) + 1:02d}-{int(m[1]):02d}"


def main():
    offline = "--offline" in sys.argv[1:]
    if offline and ADVISORIES.exists():
        advisories = json.loads(ADVISORIES.read_text())
    else:
        advisories = fetch_advisories()
        ADVISORIES.parent.mkdir(exist_ok=True)
        ADVISORIES.write_text(json.dumps(advisories, indent=1) + "\n")

    versions = json.loads((ROOT / "versions.json").read_text())
    previous = json.loads(COVERAGE.read_text()) if COVERAGE.exists() else {}
    coverage, untriaged = {}, 0
    for version, meta in sorted(versions.items()):
        if not meta:
            continue
        pdir = ROOT / "patches" / version
        series = [p for p in (pdir / "series").read_text().split() if not p.startswith("#")]
        known = "\n".join((pdir / p).read_text(errors="replace") for p in series) + (pdir / "debian.changelog").read_text()
        triage = {}
        if (pdir / "triage").exists():
            for line in (pdir / "triage").read_text().splitlines():
                m = TRIAGE_RE.match(line.strip())
                if m:
                    triage[m[1]] = {"status": m[2], "reason": m[3]}
        since = previous.get(version, {}).get("since") if offline else None
        since = since or release_date(meta["version"])
        rows = []
        for a in advisories:
            if a["published"] <= since:
                continue
            ids = [a["ghsa"]] + ([a["cve"]] if a["cve"] else [])
            if any(i in known for i in ids):
                status, reason = "covered", None
            elif a["ghsa"] in triage:
                status, reason = triage[a["ghsa"]]["status"], triage[a["ghsa"]]["reason"]
            else:
                status, reason = "untriaged", None
                untriaged += 1
            rows.append({**a, "status": status, "reason": reason})
        coverage[version] = {"since": since, "advisories": rows}
        counts = {s: sum(r["status"] == s for r in rows) for s in ("covered", "not-affected", "wontfix", "pending", "untriaged")}
        print(f"{version} (released {since}): " + ", ".join(f"{n} {s}" for s, n in counts.items() if n))
        for r in rows:
            if r["status"] in ("untriaged", "pending"):
                print(f"  {r['status']:9} {r['ghsa']} {r['cve'] or '':16} {r['published']} {r['severity'] or '':8} {r['summary'][:60]}")
    COVERAGE.write_text(json.dumps(coverage, indent=1) + "\n")
    return 1 if untriaged else 0


if __name__ == "__main__":
    sys.exit(main())
