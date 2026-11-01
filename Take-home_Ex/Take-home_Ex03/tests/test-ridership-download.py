"""Offline acquisition checks; no live LTA requests or third-party packages."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "R" / "acquire-ridership.py"
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("acquire_ridership", SCRIPT)
    acquisition = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(acquisition)
else:
    acquisition = None

SECRET = "fixture-key-never-print"
SIGNED = "https://fixture.invalid/archive.zip?token=never-print-this"


def fixture_zip(dataset="ODTrain", month="202608", content=None):
    prefix = "origin_destination_train" if dataset == "ODTrain" else "transport_node_train"
    if content is None:
        tail = ("ORIGIN_PT_CODE,DESTINATION_PT_CODE,TOTAL_TRIPS\n"
                "2026-08,WEEKDAY,6,TRAIN,NS1,NS2,12\n")
        if dataset == "Train":
            tail = ("PT_CODE,TOTAL_TAP_IN_VOLUME,TOTAL_TAP_OUT_VOLUME\n"
                    "2026-08,WEEKDAY,6,TRAIN,NS1,12,11\n")
        content = ("YEAR_MONTH,DAY_TYPE,TIME_PER_HOUR,PT_TYPE," + tail)
        content = content.replace("2026-08", month[:4] + "-" + month[4:])
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(f"{prefix}_{month}.csv", content)
    return buffer.getvalue()


class FixtureOpener:
    def __init__(self, corrupt=False):
        self.requests = []
        self.pending = None
        self.corrupt = corrupt

    def open(self, request, timeout):
        self.requests.append(request)
        if request.full_url.startswith("https://datamall2.mytransport.sg/"):
            dataset = request.full_url.split("/PV/")[1].split("?")[0]
            month = request.full_url.rsplit("=", 1)[1]
            self.pending = fixture_zip(dataset, month)
            return io.BytesIO(json.dumps({"value": [{"Link": SIGNED}]}).encode())
        return io.BytesIO(b"corrupt" if self.corrupt else self.pending)


class AcquisitionTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(acquisition, "The acquisition CLI is not implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_cli(self, args, environ, opener):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = acquisition.main(args, environ=environ, root=self.root, opener=opener)
        return code, out.getvalue() + err.getvalue()

    def test_no_key_check_and_download_make_zero_requests_or_files(self):
        opener = mock.Mock()
        code, output = self.run_cli(["--check"], {}, opener)
        self.assertEqual(code, 0)
        self.assertIn("absent", output)
        code, output = self.run_cli(["--download"], {}, opener)
        self.assertNotEqual(code, 0)
        self.assertIn("LTA_ACCOUNT_KEY", output)
        self.assertIn("Set", output)
        opener.open.assert_not_called()
        self.assertEqual(list(self.root.iterdir()), [])

    def test_readiness_reports_presence_without_value_or_requests(self):
        opener = mock.Mock()
        code, output = self.run_cli(["--check"], {"LTA_ACCOUNT_KEY": SECRET}, opener)
        self.assertEqual(code, 0)
        self.assertIn("present", output)
        self.assertNotIn(SECRET, output)
        opener.open.assert_not_called()
        self.assertEqual(list(self.root.iterdir()), [])

    def test_hidden_prompt_downloads_without_environment_or_saved_credential(self):
        opener = FixtureOpener()
        with mock.patch('getpass.getpass', return_value=SECRET):
            code, output = self.run_cli(['--download','--prompt'], {}, opener)
        self.assertEqual(code, 0, output)
        self.assertEqual(len(list((self.root/'data/raw').glob('*.zip'))),4)
        self.assertNotIn(SECRET,output)
        manifest=(self.root/'_workflow/ridership-acquisition.json').read_text(encoding='utf-8')
        self.assertNotIn(SECRET,manifest)

    def test_cancelled_hidden_prompt_leaves_no_downloads(self):
        opener = mock.Mock()
        with mock.patch('getpass.getpass', side_effect=EOFError):
            code, output = self.run_cli(['--download','--prompt'], {}, opener)
        self.assertNotEqual(code,0)
        self.assertIn('cancelled',output)
        opener.open.assert_not_called()
        self.assertEqual(list(self.root.iterdir()),[])

    def test_download_installs_four_valid_archives_and_safe_provenance(self):
        opener = FixtureOpener()
        code, output = self.run_cli(["--download"], {"LTA_ACCOUNT_KEY": SECRET}, opener)
        self.assertEqual(code, 0, output)
        files = sorted((self.root / "data" / "raw").glob("*.zip"))
        self.assertEqual([p.name for p in files], [
            "origin_destination_train_202608.zip", "origin_destination_train_202609.zip",
            "transport_node_train_202608.zip", "transport_node_train_202609.zip"])
        self.assertEqual(len(opener.requests), 8)
        for request in opener.requests:
            headers = {k.lower(): v for k, v in request.header_items()}
            if request.full_url.startswith("https://datamall2.mytransport.sg/"):
                self.assertEqual(headers.get("accountkey"), SECRET)
            else:
                self.assertNotIn("accountkey", headers)
                self.assertNotIn(SECRET, str(headers))
        manifest_path = self.root / "_workflow" / "ridership-acquisition.json"
        manifest_text = manifest_path.read_text(encoding="utf-8")
        manifest = json.loads(manifest_text)
        self.assertEqual(len(manifest["files"]), 4)
        by_name = {Path(record["path"]).name: record for record in manifest["files"]}
        for path in files:
            self.assertEqual(by_name[path.name]["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(by_name[path.name]["rows"], 1)
        for text in (output, manifest_text):
            self.assertNotIn(SECRET, text)
            self.assertNotIn(SIGNED, text)
            self.assertNotIn("never-print-this", text)
        self.assertEqual(list(self.root.rglob("*.part")), [])

    def test_existing_valid_archives_are_skipped_without_requests(self):
        first = FixtureOpener()
        self.assertEqual(self.run_cli(["--download"], {"LTA_ACCOUNT_KEY": SECRET}, first)[0], 0)
        before = {p.name: p.read_bytes() for p in (self.root / "data" / "raw").glob("*.zip")}
        opener = mock.Mock()
        code, output = self.run_cli(["--download"], {"LTA_ACCOUNT_KEY": SECRET}, opener)
        self.assertEqual(code, 0, output)
        opener.open.assert_not_called()
        self.assertEqual(before, {p.name: p.read_bytes() for p in (self.root / "data" / "raw").glob("*.zip")})

    def test_corrupt_download_never_becomes_final_archive(self):
        code, output = self.run_cli(["--download"], {"LTA_ACCOUNT_KEY": SECRET}, FixtureOpener(corrupt=True))
        self.assertNotEqual(code, 0)
        self.assertEqual(list(self.root.rglob("*.zip")), [])
        self.assertEqual(list(self.root.rglob("*.part")), [])
        self.assertNotIn(SIGNED, output)

    def test_zip_validation_rejects_wrong_month_schema_values_and_crc(self):
        path = self.root / "fixture.zip"
        good = fixture_zip()
        path.write_bytes(good)
        result = acquisition.validate_archive(path, "ODTrain", "202608")
        self.assertEqual(result["rows"], 1)
        for content in [
            "YEAR_MONTH,DAY_TYPE\n2026-08,WEEKDAY\n",
            "YEAR_MONTH,DAY_TYPE,TIME_PER_HOUR,PT_TYPE,ORIGIN_PT_CODE,DESTINATION_PT_CODE,TOTAL_TRIPS\n"
            "2026-07,WEEKDAY,6,TRAIN,NS1,NS2,12\n",
            "YEAR_MONTH,DAY_TYPE,TIME_PER_HOUR,PT_TYPE,ORIGIN_PT_CODE,DESTINATION_PT_CODE,TOTAL_TRIPS\n"
            "2026-08,WEEKDAY,6,TRAIN,NS1,NS2,-1\n",
            "YEAR_MONTH,DAY_TYPE,TIME_PER_HOUR,PT_TYPE,ORIGIN_PT_CODE,DESTINATION_PT_CODE,TOTAL_TRIPS\n",
        ]:
            path.write_bytes(fixture_zip(content=content))
            with self.assertRaises(acquisition.AcquisitionError):
                acquisition.validate_archive(path, "ODTrain", "202608")
        # Damage a compressed member, preserving the central directory.
        damaged = bytearray(good)
        with zipfile.ZipFile(io.BytesIO(good)) as archive:
            entry = archive.infolist()[0]
            offset = entry.header_offset + 30 + len(entry.filename.encode()) + len(entry.extra)
            damaged[offset + entry.compress_size // 2] ^= 255
        path.write_bytes(damaged)
        with self.assertRaises(acquisition.AcquisitionError):
            acquisition.validate_archive(path, "ODTrain", "202608")

    def test_transport_errors_cannot_echo_secrets_or_signed_urls(self):
        opener = mock.Mock()
        opener.open.side_effect = RuntimeError(SECRET + " " + SIGNED + " response-body")
        code, output = self.run_cli(["--download"], {"LTA_ACCOUNT_KEY": SECRET}, opener)
        self.assertNotEqual(code, 0)
        for hidden in (SECRET, SIGNED, "response-body"):
            self.assertNotIn(hidden, output)
        self.assertEqual(list(self.root.rglob("*.zip")), [])

    def test_credential_requests_do_not_follow_redirects(self):
        request = acquisition.urllib.request.Request(
            "https://datamall2.mytransport.sg/ltaodataservice/PV/Train?Date=202608",
            headers={"AccountKey": SECRET})
        handler = acquisition.NoRedirect()
        self.assertIsNone(handler.redirect_request(request, None, 302, "", {}, SIGNED))


if __name__ == "__main__":
    unittest.main(verbosity=2)
