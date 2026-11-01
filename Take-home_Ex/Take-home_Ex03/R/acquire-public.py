#!/usr/bin/env python3
"""Explicit public-input acquisition for Ex03. Never called during Quarto render.

Default: offline verification. Run --download only when acquiring missing public
files/copying supplied originals. Existing originals are never replaced.
Python stdlib suffices; recreating station-codes.csv also needs R + readxl.
"""
from __future__ import annotations

import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
SOURCES = ROOT / "data" / "metadata"
CATALOG_PATH = SOURCES / "public-source-catalog.json"
MANIFEST = ROOT / "_workflow" / "acquisition.json"
USER_AGENT = "Mozilla/5.0 (coursework public-data acquisition)"
ATTEMPTS = 3
TIMEOUT_SECONDS = 40


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def atomic_json(path, obj):
    """Replace derived metadata, never an original data file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temp.replace(path)


def fetch(url):
    """Public GET only, no cookies, keys, session files, or automatic auth."""
    last_error = "Unknown network failure"
    for attempt in range(ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            # Do not include URLs: a public data.gov redirect can be signed.
            last_error = f"HTTP {exc.code}"
            if exc.code not in (408, 429, 500, 502, 503, 504):
                break
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = type(exc).__name__
        if attempt + 1 < ATTEMPTS:
            time.sleep(attempt + 1)
    raise RuntimeError(f"Public GET failed after at most {ATTEMPTS} attempts: {last_error}")


def install_original(path, data, expected_hash):
    actual = sha256(data)
    if actual != expected_hash:
        raise ValueError(f"{path.name}: source hash differs from pinned snapshot; original not written")
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"{path.name}: existing original differs; refusing replacement")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation protects an original if two acquisitions are launched.
    with path.open("xb") as stream:
        stream.write(data)
    return True


def rscript_path(override=None):
    if override:
        return str(Path(override).resolve())
    found = shutil.which("Rscript")
    if found:
        return found
    program_files = Path(os.environ.get("ProgramFiles", "C:/Program Files"))
    choices = sorted((program_files / "R").glob("R-*/bin/Rscript.exe"))
    if choices:
        return str(choices[-1])
    raise RuntimeError("Rscript not found; pass --rscript. CSV derivative requires installed R readxl.")


def convert_station_csv(xls_path, rscript=None):
    """Return a deterministic UTF-8/LF CSV; keep the unmodified XLS separately."""
    with tempfile.TemporaryDirectory(prefix="ex03-station-codes-") as tempdir:
        csv_path = Path(tempdir) / "station-codes.csv"
        r_path = Path(tempdir) / "convert.R"
        # R on Windows may inherit the invalid C.UTF-8 locale from a shell.
        # Explicitly select a supported UTF-8 locale before writing Chinese.
        code = r'''
args <- commandArgs(trailingOnly = TRUE)
if (.Platform$OS.type == "windows") {
  selected <- suppressWarnings(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
  if (!nzchar(selected)) stop("A Windows UTF-8 locale is required")
}
if (!requireNamespace("readxl", quietly = TRUE)) stop("R package readxl is required")
x <- readxl::read_excel(args[1])
expected <- c("stn_code", "mrt_station_english", "mrt_station_chinese",
              "mrt_line_english", "mrt_line_chinese")
if (!identical(names(x), expected) || nrow(x) != 213L) stop("Unexpected station-code XLS schema")
utils::write.csv(x, args[2], row.names = FALSE, fileEncoding = "UTF-8")
'''
        r_path.write_text(code, encoding="utf-8")
        env = os.environ.copy()
        for key in ("LC_ALL", "LC_CTYPE", "LC_COLLATE", "LC_MONETARY", "LC_TIME"):
            env.pop(key, None)
        result = subprocess.run(
            [rscript_path(rscript), "--vanilla", str(r_path), str(xls_path), str(csv_path)],
            capture_output=True, text=True, timeout=60, env=env,
        )
        if result.returncode:
            raise RuntimeError("Station-code CSV conversion failed: " + result.stderr.strip()[-1000:])
        data = csv_path.read_bytes().replace(b"\r\n", b"\n")
        if b"<U+" in data or "\u88d5".encode("utf-8") not in data:
            raise ValueError("Station mapping Chinese text did not survive UTF-8 conversion")
        return data


def source_access(item):
    try:
        data = fetch(item["url"])
        title_match = re.search(br"<title[^>]*>(.*?)</title>", data, re.I | re.S)
        return {
            **item, "status": "retrieved", "acquired_utc": utc_now(),
            "sha256": sha256(data), "bytes": len(data),
            "title": re.sub(r"\s+", " ", title_match.group(1).decode("utf-8", "replace")).strip()
                     if title_match else None,
            "body_retained": False,
        }
    except Exception as exc:
        return {**item, "status": "failed", "attempted_utc": utc_now(),
                "failure": str(exc), "body_retained": False}


def existing_rows():
    previous = read_json(MANIFEST, {})
    rows = {row["filename"]: row for row in previous.get("files", [])}
    # Bootstrap timestamps from the actual first acquisition, not file mtime.
    for row in read_json(SOURCES / "initial-acquisition.json", []):
        rows.setdefault(row["filename"], row)
    return rows


def acquire(args, catalog):
    previous = existing_rows()
    errors = []
    for item in catalog["files"]:
        path = RAW / item["filename"]
        key = path.relative_to(ROOT).as_posix()
        try:
            if path.exists():
                if sha256(path.read_bytes()) != item["sha256"]:
                    raise ValueError(f"{path.name}: existing file differs from pinned SHA-256")
                print(f"retained {path.name}")
                continue
            kind = item["kind"]
            if kind == "local-copy":
                if path.name.startswith("train-"):
                    local = args.local_train
                else:
                    local = args.local_population_dir / Path(item["local_source"]).name
                data = local.read_bytes()
            elif kind == "public-download":
                data = fetch(item["source_url"])
            elif kind == "data-gov-poll":
                response = json.loads(fetch(item["source_url"]))
                url = response.get("data", {}).get("url")
                if response.get("code") != 0 or not url:
                    raise RuntimeError("Public data.gov poll-download returned no ready URL")
                data = fetch(url)  # Expiring URL intentionally never persisted.
            elif kind == "zip-member":
                with zipfile.ZipFile(RAW / item["parent"]) as archive:
                    data = archive.read(item["member"])
            elif kind == "xls-to-csv":
                data = convert_station_csv(RAW / item["parent"], args.rscript)
            else:
                raise ValueError(f"Unknown acquisition kind {kind}")
            install_original(path, data, item["sha256"])
            previous[key] = {"acquired_utc": utc_now()}
            print(f"acquired {path.name}")
        except Exception as exc:
            errors.append({"filename": key, "failure": str(exc), "attempted_utc": utc_now()})
            print(f"FAILED {path.name}: {exc}", file=sys.stderr)

    access_path = SOURCES / "source-access.json"
    access = read_json(access_path, [])
    known_ids = {x["id"] for x in access}
    missing = [x for x in catalog["sources"] if x["id"] not in known_ids]
    if missing:
        with ThreadPoolExecutor(max_workers=5) as pool:
            access.extend(pool.map(source_access, missing))
        atomic_json(access_path, access)

    rows = []
    for item in catalog["files"]:
        path = RAW / item["filename"]
        if not path.exists():
            continue
        key = path.relative_to(ROOT).as_posix()
        data = path.read_bytes()
        rows.append({
            **item, "filename": key, "bytes": len(data), "sha256": sha256(data),
            "acquired_utc": previous.get(key, {}).get("acquired_utc", utc_now()),
            "verified_utc": utc_now(),
        })
    evidence = []
    for path in sorted(SOURCES.glob("*")):
        if path.is_file():
            data = path.read_bytes()
            evidence.append({"filename": path.relative_to(ROOT).as_posix(),
                             "sha256": sha256(data), "bytes": len(data)})
    atomic_json(MANIFEST, {
        "schema_version": 1, "generated_utc": utc_now(), "reference_month": "2026-09",
        "github_commit": catalog["github_commit"], "files": rows,
        "evidence_files": evidence, "failures": errors,
        "source_document_failures": [x for x in access if x["status"] == "failed"],
        "limitations": catalog["limitations"], "policy": catalog["acquisition_policy"],
        "passenger_input_scope": (
            "Monthly train OD and station-volume archives are acquired separately "
            "with R/acquire-ridership.py and validated by R/02-prepare-ridership.R. "
            "This public-input manifest does not determine their availability."
        ),
    })
    return 1 if errors else verify(catalog)


def verify(catalog):
    if not MANIFEST.exists():
        print("No acquisition.json yet. Explicitly run --download to acquire and catalogue inputs.", file=sys.stderr)
        return 1
    manifest = read_json(MANIFEST, {})
    failures = []
    tracked = {x["filename"]: x for x in manifest.get("files", [])}
    for item in catalog["files"]:
        path = RAW / item["filename"]
        key = path.relative_to(ROOT).as_posix()
        if not path.exists():
            failures.append(f"Missing {key}")
            continue
        data = path.read_bytes()
        digest = sha256(data)
        if digest != item["sha256"] or digest != tracked.get(key, {}).get("sha256"):
            failures.append(f"Hash mismatch: {key}")
    for item in manifest.get("evidence_files", []):
        path = ROOT / item["filename"]
        if not path.exists() or sha256(path.read_bytes()) != item["sha256"]:
            failures.append(f"Evidence changed/missing: {item['filename']}")
    for filename in ("train-stations-sep2026.zip", "bus-stops-sep2026.zip", "station-codes.zip"):
        path = RAW / filename
        if path.exists():
            try:
                with zipfile.ZipFile(path) as archive:
                    if archive.testzip():
                        failures.append(f"Invalid ZIP content: {filename}")
            except zipfile.BadZipFile:
                failures.append(f"Unreadable ZIP: {filename}")
    geo_path = RAW / "subzones-mp2019.geojson"
    if geo_path.exists() and len(json.loads(geo_path.read_text(encoding="utf-8"))["features"]) != 332:
        failures.append("Unexpected subzone feature count")
    map_path = RAW / "station-codes.csv"
    if map_path.exists():
        text = map_path.read_text(encoding="utf-8-sig")
        rows = list(csv.DictReader(io.StringIO(text)))
        if len(rows) != 213 or "<U+" in text:
            failures.append("Unexpected station-code CSV schema or Chinese encoding")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print(f"Verified {len(catalog['files'])} public data files and {len(manifest.get('evidence_files', []))} evidence files offline.")
    print("Public-source verification complete; passenger archives are validated separately.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="Offline hashes/archives/schema (default)")
    mode.add_argument("--download", action="store_true", help="Explicitly acquire missing public files and build manifest")
    parser.add_argument("--local-train", type=Path, default=Path.home() / "Downloads" / "TrainStation_Sep2026.zip")
    parser.add_argument("--local-population-dir", type=Path,
                        default=Path.home() / "Downloads" / "\u7b2c\u4e8c\u5b66\u671f" / "respopagesextod2025")
    parser.add_argument("--rscript", help="Rscript executable if not on PATH")
    args = parser.parse_args()
    catalog = read_json(CATALOG_PATH, {})
    if not catalog:
        parser.error("Missing public-source-catalog.json")
    return acquire(args, catalog) if args.download else verify(catalog)


if __name__ == "__main__":
    raise SystemExit(main())
