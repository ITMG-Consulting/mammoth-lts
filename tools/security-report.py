#!/usr/bin/env python3
"""Generates SECURITY.md: per PHP branch, the security fixes backported on top of the last upstream release.

Source: patches/<version>/debian.changelog (deb.sury.org), entries for the last upstream release only
(e.g. 7.2.34-N), items listed under "Backported from X" or tagged with a CVE/GHSA identifier.
Each identifier is cross-checked against the text of the patches actually applied (patches/<version>/series).
"""
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# CVSS score / severity and publication date per identifier, fetched once (CVE.org, GitHub php-src advisories)
CACHE = ROOT / "data" / "advisories.json"
CVSS_ORDER = ["cvssV4_0", "cvssV3_1", "cvssV3_0", "cvssV2_0"]
BADGE_COLOR = {"CRITICAL": "critical", "HIGH": "orange", "MEDIUM": "yellow", "LOW": "green"}
ID_RE = re.compile(r"CVE-\d{4}-\d{4,}|GHSA(?:-[0-9a-z]{4}){3}|(?:bug )?#\d{5}")
HEADER_RE = re.compile(r"^php[\d.]+ \((?:\d+:)?(?P<upstream>[\d.]+)-(?P<rev>\d+)\)")
TRAILER_RE = re.compile(r"^ -- .+?  (?P<date>.+)$")


def parse_changelog(path, upstream):
    """Yields (revision, date, backported_from, text) for each security item of the given upstream release."""
    entries, cur = [], None
    for line in path.read_text().splitlines():
        m = HEADER_RE.match(line)
        if m:
            cur = {"rev": int(m["rev"]), "upstream": m["upstream"], "lines": []} if m["upstream"] == upstream else None
            if cur:
                entries.append(cur)
            continue
        if cur is None:
            continue
        m = TRAILER_RE.match(line)
        if m:
            cur["date"] = m["date"]
            continue
        cur["lines"].append(line)

    for e in entries:
        source, item = None, None
        items = []
        for line in e["lines"]:
            stripped = line.strip()
            m = re.match(r"^\* Backported from (?:PHP )?([\d.]+)", stripped)
            if m:
                source, item = m[1], None
                continue
            if re.match(r"^\* ", stripped):
                source = None
                item = [stripped[2:]] if re.search(r"CVE-|GHSA-", stripped) else None
                if item:
                    items.append((None, item))
                continue
            if re.match(r"^[+.] ", stripped) and (source or ID_RE.search(stripped)):
                item = [stripped[2:]]
                items.append((source, item))
                continue
            if item is not None and stripped and not stripped.startswith("- "):
                item.append(stripped)
            elif not stripped:
                item = None
        for source, item in items:
            text = " ".join(item)
            if source is None and not re.search(r"CVE-|GHSA-", text):
                continue
            yield e["rev"], e.get("date", ""), source, text


def fetch_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "mammoth-lts"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch_advisory(ident):
    """{"published", "cvssVersion", "score", "severity"} from CVE.org (CVE) or the php-src GitHub advisory (GHSA)."""
    if ident.startswith("CVE-"):
        d = fetch_json(f"https://cveawg.mitre.org/api/cve/{ident}")
        metrics = []
        for cont in [d["containers"].get("cna", {}), *d["containers"].get("adp", [])]:
            for m in cont.get("metrics", []):
                metrics += [(k, v) for k, v in m.items() if k in CVSS_ORDER]
        metrics.sort(key=lambda kv: CVSS_ORDER.index(kv[0]))
        k, v = metrics[0] if metrics else (None, {})
        return {
            "published": d["cveMetadata"].get("datePublished", "")[:10],
            "cvssVersion": k and k[5:].replace("_", "."),
            "score": v.get("baseScore"),
            "severity": (v.get("baseSeverity") or "").upper() or None,
        }
    d = fetch_json(f"https://api.github.com/repos/php/php-src/security-advisories/{ident}")
    cvss = d.get("cvss_severities") or {}
    version, score = next(((ver, c["score"]) for ver, c in (("4.0", cvss.get("cvss_v4") or {}), ("3.1", cvss.get("cvss_v3") or {})) if c.get("score")), (None, None))
    return {"published": (d.get("published_at") or "")[:10], "cvssVersion": version, "score": score, "severity": (d.get("severity") or "").upper() or None}


def advisories(idents, refresh=False):
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    for ident in sorted(idents):
        if refresh or ident not in cache:
            try:
                cache[ident] = fetch_advisory(ident)
            except Exception as e:  # keep the report buildable offline, the cell shows "n/a"
                print(f"warning: {ident}: {e}", file=sys.stderr)
    CACHE.parent.mkdir(exist_ok=True)
    CACHE.write_text(json.dumps(dict(sorted(cache.items())), indent=1) + "\n")
    return cache


def ident_cell(ident, meta):
    url = f"https://nvd.nist.gov/vuln/detail/{ident}" if ident.startswith("CVE-") else f"https://github.com/php/php-src/security/advisories/{ident}"
    if meta and meta.get("score") is not None:
        label = urllib.parse.quote(f"CVSS {meta['cvssVersion'] or ''}".strip().replace("-", "--"))
        message = urllib.parse.quote(f"{meta['score']} {meta['severity'] or ''}".strip())
        color = BADGE_COLOR.get(meta["severity"], "lightgrey")
        badge = f"![CVSS](https://img.shields.io/badge/{label}-{message}-{color})"
    else:
        badge = "![CVSS](https://img.shields.io/badge/CVSS-n%2Fa-lightgrey)"
    return f"[{ident}]({url})<br>{badge}"


def short_date(date):
    m = re.search(r"(\d{1,2}) (\w{3}) (\d{4})", date)
    months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    return f"{m[3]}-{months.index(m[2]) + 1:02d}-{int(m[1]):02d}" if m else date


def main():
    refresh = "--refresh" in sys.argv[1:]
    coverage_file = ROOT / "data" / "coverage.json"
    coverage = json.loads(coverage_file.read_text()) if coverage_file.exists() else {}
    versions = json.loads((ROOT / "versions.json").read_text())
    out = [
        "# Security fixes",
        "",
        "Fixes backported on top of the last upstream release of each end-of-life branch.",
        "Generated by `tools/security-report.py` from the deb.sury.org changelog shipped in `patches/<version>/debian.changelog`;",
        "every identifier is checked against the patches actually applied (`patches/<version>/series`).",
        "",
    ]
    for version, meta in sorted(versions.items(), key=lambda kv: [int(x) for x in kv[0].split(".")]):
        if not meta:
            continue
        pdir = ROOT / "patches" / version
        upstream = meta["version"]
        patchlevel = (pdir / "patchlevel").read_text().strip()
        series = [p for p in (pdir / "series").read_text().split() if not p.startswith("#")]
        patch_text = "\n".join((pdir / p).read_text(errors="replace") for p in series)

        items, cves, missing = [], set(), set()
        for rev, date, source, text in parse_changelog(pdir / "debian.changelog", upstream):
            ids = sorted(set(i for i in ID_RE.findall(text) if not i.startswith(("#", "bug"))))
            cves.update(i for i in ids if i.startswith("CVE"))
            missing.update(i for i in ids if i not in patch_text)
            items.append((rev, date, source, ids, re.sub(r"\s+", " ", text).replace("|", "\\|")))
        meta = advisories({i for *_, ids, _ in items for i in ids}, refresh)
        rows = []
        for rev, date, source, ids, text in items:
            published = min((meta.get(i, {}).get("published") or "9999" for i in ids), default="") if ids else ""
            published = "" if published == "9999" else published
            cells = "<br>".join(ident_cell(i, meta.get(i)) for i in ids) or "—"
            rows.append((rev, f"| {cells} | {published or '—'} | {text} | {source or '—'} | {short_date(date)} (Sury {rev}) |"))

        out += [
            f"## PHP {version} — `{upstream}-p{patchlevel}`",
            "",
            f"{len(cves)} CVE fixed since the {upstream} release, {len(series)} patches applied.",
            "",
            "| Advisory | Published | Fix | Backported from | Fixed here |",
            "| --- | --- | --- | --- | --- |",
            *(row for _, row in sorted(rows, key=lambda r: -r[0])),
            "",
        ]
        cov = coverage.get(version)
        if cov:
            open_rows = [a for a in cov["advisories"] if a["status"] != "covered"]
            covered = sum(a["status"] == "covered" for a in cov["advisories"])
            out += [
                f"### php-src advisories since {cov['since']}",
                "",
                f"{len(cov['advisories'])} advisories published by php-src after the {upstream} release: {covered} covered by the patches above,"
                f" {len(open_rows)} below. `untriaged` means nobody has checked yet whether {version} is affected (`tools/advisory-coverage.py`).",
                "",
            ]
            if open_rows:
                out += ["| Advisory | Published | Summary | Status |", "| --- | --- | --- | --- |"]
                for a in sorted(open_rows, key=lambda a: a["published"], reverse=True):
                    ids = [a["ghsa"]] + ([a["cve"]] if a["cve"] else [])
                    meta = {"cvssVersion": None, "score": a["score"], "severity": a["severity"]}
                    cells = "<br>".join(ident_cell(i, meta) for i in ids[:1]) + (f"<br>{a['cve']}" if a["cve"] else "")
                    status = a["status"] + (f": {a['reason']}" if a["reason"] else "")
                    out.append(f"| {cells} | {a['published']} | {a['summary'].replace('|', '/')} | {status} |")
                out.append("")
        if missing:
            out += [
                "Identifiers not found in the applied patch texts (usually platform-specific fixes, e.g. Windows only, or a fix"
                " whose patch does not quote its identifier): " + ", ".join(sorted(missing)) + ".",
                "",
            ]
    Path(ROOT / "SECURITY.md").write_text("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
