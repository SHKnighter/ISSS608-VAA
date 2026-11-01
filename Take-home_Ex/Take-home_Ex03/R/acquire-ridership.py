"""Explicit LTA acquisition; importing or rendering never starts a download.

Usage: python R/acquire-ridership.py --check
       python R/acquire-ridership.py --download
       python R/acquire-ridership.py --download --prompt
Set LTA_ACCOUNT_KEY locally; never put the key in source or command arguments.
Contract: LTA DataMall API User Guide v6.11, sections 2.7/2.8, Annexes A/B:
https://datamall.lta.gov.sg/content/dam/datamall/datasets/LTA_DataMall_API_User_Guide.pdf
"""
import argparse
import csv
import getpass
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

MONTHS = ("202608", "202609")
DATASETS = {"ODTrain": "origin_destination_train", "Train": "transport_node_train"}
BASE_URL = "https://datamall2.mytransport.sg/ltaodataservice/PV/"
GUIDE_URL = "https://datamall.lta.gov.sg/content/dam/datamall/datasets/LTA_DataMall_API_User_Guide.pdf"
TIMEOUT = 30
MAX_ZIP_BYTES = 256 * 1024 * 1024
MAX_CSV_BYTES = 2 * 1024 * 1024 * 1024


class AcquisitionError(Exception):
    """Contains only controlled messages, never transport exception text."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # In particular, never forward AccountKey to a redirect destination.
        return None


def validate_archive(path, dataset, month):
    """Read every CSV row (including ZIP CRC), without extracting any member."""
    try:
        expected = f"{DATASETS[dataset]}_{month}.csv"
        schema = ["YEAR_MONTH", "DAY_TYPE", "TIME_PER_HOUR", "PT_TYPE"]
        if dataset == "ODTrain":
            schema += ["ORIGIN_PT_CODE", "DESTINATION_PT_CODE", "TOTAL_TRIPS"]
            counts = ["TOTAL_TRIPS"]
            codes = ["ORIGIN_PT_CODE", "DESTINATION_PT_CODE"]
        else:
            schema += ["PT_CODE", "TOTAL_TAP_IN_VOLUME", "TOTAL_TAP_OUT_VOLUME"]
            counts = ["TOTAL_TAP_IN_VOLUME", "TOTAL_TAP_OUT_VOLUME"]
            codes = ["PT_CODE"]
        with zipfile.ZipFile(path) as archive:
            members = [m for m in archive.infolist() if not m.is_dir()]
            if (len(members) != 1 or members[0].filename != expected
                    or members[0].file_size > MAX_CSV_BYTES or members[0].flag_bits & 1):
                raise ValueError("unexpected archive members")
            with archive.open(members[0]) as raw, io.TextIOWrapper(raw, encoding="utf-8-sig", newline="") as text:
                reader = csv.reader(text, skipinitialspace=True)
                header = next(reader)
                header = [field.strip() for field in header]
                if len(header) != len(set(header)) or not set(schema).issubset(header):
                    raise ValueError("unexpected schema")
                indices = {name: header.index(name) for name in schema}
                rows = 0
                for record in reader:
                    if len(record) != len(header):
                        raise ValueError("malformed row")
                    row = {name: record[index].strip() for name, index in indices.items()}
                    if (row["YEAR_MONTH"] != month[:4] + "-" + month[4:]
                            or row["PT_TYPE"] != "TRAIN"
                            or row["DAY_TYPE"] not in ("WEEKDAY", "WEEKENDS/HOLIDAY")
                            or not row["TIME_PER_HOUR"].isascii()
                            or not row["TIME_PER_HOUR"].isdigit()
                            or not 0 <= int(row["TIME_PER_HOUR"]) <= 23
                            or any(not row[name] for name in codes)
                            or any(not row[name].isascii() or not row[name].isdigit() for name in counts)):
                        raise ValueError("invalid month or values")
                    rows += 1
                if not rows:
                    raise ValueError("empty CSV")
        digest = hashlib.sha256()
        with Path(path).open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        return {"sha256": digest.hexdigest(), "bytes": Path(path).stat().st_size,
                "csv_members": 1, "rows": rows}
    except Exception:
        raise AcquisitionError("Archive validation failed (ZIP/CRC, CSV schema, month, or values).") from None


def _signed_link(opener, dataset, month, key):
    import socket
    import ssl
    from urllib.error import HTTPError, URLError

    endpoint = f"PV/{dataset} {month[:4]}-{month[4:]}"

    def transport_cause(reason):
        if isinstance(reason, ssl.SSLCertVerificationError):
            return "TLS certificate verification failed; check the local certificate/proxy setup."
        if isinstance(reason, ssl.SSLError):
            return "TLS connection failed; check the local network/proxy setup."
        if isinstance(reason, socket.gaierror):
            return "DNS lookup failed; check the internet connection and DNS settings."
        if isinstance(reason, TimeoutError):
            return "Request timed out; check connectivity and try again later."
        return "Network connection failed; check internet, proxy, or firewall access."

    try:
        request = urllib.request.Request(BASE_URL + dataset + "?Date=" + month,
                                         headers={"AccountKey": key, "Accept": "application/json"})
        with opener.open(request, timeout=TIMEOUT) as response:
            body = response.read(65537)
    except HTTPError as error:
        status = error.code
        causes = {
            401: "API key rejected; it may be invalid or not activated. Use the DataMall API Access Key; SDK credentials are separate.",
            403: "Access denied; check API permissions and account activation.",
            404: "Resource not found; the endpoint or requested month may be unavailable. Check the official API documentation and monthly availability.",
            429: "Request throttled; wait before trying again.",
        }
        cause = ("LTA service error; try again later." if 500 <= status <= 599 else
                 causes.get(status, "Request rejected; check endpoint, month, and account access."))
        raise AcquisitionError(f"{endpoint}: HTTP {status}. {cause}") from None
    except URLError as error:
        raise AcquisitionError(f"{endpoint}: {transport_cause(error.reason)}") from None
    except (ssl.SSLError, socket.gaierror, TimeoutError) as error:
        raise AcquisitionError(f"{endpoint}: {transport_cause(error)}") from None
    except Exception:
        raise AcquisitionError(f"{endpoint}: Metadata request could not be completed; check local connectivity and API access.") from None
    if len(body) > 65536:
        raise AcquisitionError(f"{endpoint}: HTTP 200 metadata exceeded the response size limit.") from None
    try:
        payload = json.loads(body)
    except (ValueError, UnicodeError):
        raise AcquisitionError(f"{endpoint}: HTTP 200 returned malformed JSON metadata.") from None
    if not isinstance(payload, dict) or not isinstance(payload.get("value"), list):
        raise AcquisitionError(f"{endpoint}: HTTP 200 returned an unexpected metadata schema.") from None
    records = payload["value"]
    if not records:
        raise AcquisitionError(f"{endpoint}: HTTP 200; monthly archive unavailable (empty value).") from None
    if len(records) != 1 or not isinstance(records[0], dict) or "Link" not in records[0]:
        raise AcquisitionError(f"{endpoint}: HTTP 200 returned an unexpected metadata schema.") from None
    link = records[0]["Link"]
    if link is None or (isinstance(link, str) and not link.strip()):
        raise AcquisitionError(f"{endpoint}: HTTP 200; monthly archive unavailable (blank Link).") from None
    if not isinstance(link, str):
        raise AcquisitionError(f"{endpoint}: HTTP 200 returned an unexpected metadata schema.") from None
    try:
        link = link.strip()
        parsed = urllib.parse.urlsplit(link)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username
                or parsed.password or parsed.fragment):
            raise ValueError("invalid download link")
        return link
    except Exception:
        raise AcquisitionError(f"{endpoint}: HTTP 200 returned an invalid HTTPS download link.") from None


def _download(opener, link, target, dataset, month):
    temporary = None
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, name = tempfile.mkstemp(prefix=target.name + ".", suffix=".part", dir=target.parent)
        temporary = Path(name)
        # A fresh Request intentionally has no AccountKey or Authorization header.
        request = urllib.request.Request(link, headers={"Accept": "application/zip"})
        started = time.monotonic()
        with os.fdopen(descriptor, "wb") as output, opener.open(request, timeout=TIMEOUT) as response:
            size = 0
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_ZIP_BYTES or time.monotonic() - started > 120:
                    raise AcquisitionError("Archive transfer exceeded its size or time bound.")
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        result = validate_archive(temporary, dataset, month)
        os.replace(temporary, target)
        return result
    except AcquisitionError:
        raise
    except Exception:
        raise AcquisitionError("Archive transfer failed; check connectivity and local storage, then rerun --download.") from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _write_manifest(root, records):
    target = root / "_workflow" / "ridership-acquisition.json"
    temporary = None
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, name = tempfile.mkstemp(prefix=target.name + ".", suffix=".part", dir=target.parent)
        temporary = Path(name)
        payload = {"source": "LTA DataMall", "documentation": GUIDE_URL, "files": records}
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
            json.dump(payload, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
    except Exception:
        raise AcquisitionError("Could not write acquisition provenance; check local storage and rerun --download.") from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def acquire(root, key, opener=None):
    if not key or not key.strip():
        raise AcquisitionError("Set LTA_ACCOUNT_KEY in your local environment, then rerun --download. No requests were made.")
    root = Path(root)
    opener = opener if opener is not None else urllib.request.build_opener(NoRedirect())
    records = []
    # Four fixed assets, at most one metadata and one archive request each; no retries.
    for dataset, prefix in DATASETS.items():
        for month in MONTHS:
            relative = Path("data") / "raw" / f"{prefix}_{month}.zip"
            target = root / relative
            if target.exists():
                print(f"Validating existing archive: {target.name}...", flush=True)
                try:
                    details = validate_archive(target, dataset, month)
                except AcquisitionError:
                    raise AcquisitionError("An existing raw archive failed validation; move it aside and rerun --download.") from None
                status = "existing_validated"
            else:
                print(f"Requesting PV/{dataset} {month[:4]}-{month[4:]}...", flush=True)
                link = _signed_link(opener, dataset, month, key.strip())
                print(f"Downloading and validating ZIP/CSV: {target.name}...", flush=True)
                details = _download(opener, link, target, dataset, month)
                status = "downloaded"
            records.append({"dataset": dataset, "month": month, "path": relative.as_posix(),
                            "endpoint": BASE_URL + dataset + "?Date=" + month,
                            "validated_utc": datetime.now(timezone.utc).isoformat(),
                            "status": status, **details})
            _write_manifest(root, records)
            print(f"{status}: {target.name}", flush=True)
    return records


def main(argv=None, *, environ=None, root=None, opener=None):
    parser = argparse.ArgumentParser(description="Explicitly acquire the four Aug/Sep 2026 LTA train-volume archives.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Report key readiness only; never access the network or write files.")
    mode.add_argument("--download", action="store_true", help="Validate existing files and explicitly download missing archives.")
    parser.add_argument("--prompt", action="store_true", help="Read the DataMall API key using a hidden local prompt; requires --download.")
    args = parser.parse_args(argv)
    if args.prompt and not args.download:
        parser.error('--prompt requires --download')
    environment = os.environ if environ is None else environ
    key = environment.get("LTA_ACCOUNT_KEY", "")
    if args.check:
        print("LTA_ACCOUNT_KEY is " + ("present." if key.strip() else "absent. Set it locally before --download."))
        return 0
    try:
        if args.prompt:
            print('Use the DataMall API Access Key email. The SDK Account Key is a separate credential.')
            try:
                key = getpass.getpass('DataMall API Access Key (hidden input): ')
            except (EOFError, KeyboardInterrupt):
                raise AcquisitionError('Key entry cancelled; no requests were made.') from None
        acquire(Path(__file__).resolve().parents[1] if root is None else root, key, opener)
        return 0
    except AcquisitionError as error:
        print(str(error), file=sys.stderr)
        return 2
    except Exception:
        print("Acquisition failed; check local access and storage before rerunning --download.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
