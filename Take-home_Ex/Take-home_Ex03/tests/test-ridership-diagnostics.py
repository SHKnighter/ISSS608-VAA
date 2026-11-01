"""Offline tests of production metadata diagnostics; all credentials are fixtures."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import socket
import ssl
import sys
import tempfile
import unittest
import urllib.error

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "R" / "acquire-ridership.py"
spec = importlib.util.spec_from_file_location("ridership_diagnostics", SCRIPT)
acquisition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acquisition)
SECRET = "diagnostic-fixture-secret"
SIGNED = "https://fixture.invalid/archive.zip?token=diagnostic-hidden-token"
PRIVATE = SECRET + " " + SIGNED + " private-response-body"


class Reply:
    def __init__(self, body=None, error=None, before_open=None):
        self.body = body
        self.error = error
        self.before_open = before_open

    def open(self, request, timeout):
        if self.before_open:
            self.before_open()
        if self.error is not None:
            raise self.error
        return io.BytesIO(self.body)


class MetadataDiagnosticsTests(unittest.TestCase):
    def error_message(self, *, body=None, error=None):
        with self.assertRaises(acquisition.AcquisitionError) as result:
            acquisition._signed_link(Reply(body, error), "ODTrain", "202608", SECRET)
        message = str(result.exception)
        self.assertIn("PV/ODTrain", message)
        self.assertIn("2026-08", message)
        for hidden in (SECRET, SIGNED, "diagnostic-hidden-token", "private-response-body"):
            self.assertNotIn(hidden, message)
        self.assertTrue(result.exception.__suppress_context__)
        return message.lower()

    def test_http_statuses_have_distinct_actionable_causes(self):
        cases = [(401, "key"), (403, "access denied"), (404, "endpoint"),
                 (429, "throttl"), (500, "service"), (503, "service"), (400, "request")]
        for status, cause in cases:
            with self.subTest(status=status):
                error = urllib.error.HTTPError(SIGNED, status, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
                message = self.error_message(error=error)
                self.assertIn(f"http {status}", message)
                self.assertIn(cause, message)
                if status == 401:
                    self.assertIn("activat", message)
                if status == 404:
                    self.assertIn("month", message)

    def test_dns_tls_certificate_and_timeout_are_distinct(self):
        cases = [(socket.gaierror(socket.EAI_NONAME, PRIVATE), "dns"),
                 (ssl.SSLCertVerificationError(1, PRIVATE), "certificate"),
                 (ssl.SSLError(1, PRIVATE), "tls"),
                 (TimeoutError(PRIVATE), "timed out"),
                 (ConnectionRefusedError(PRIVATE), "connection")]
        for cause, expected in cases:
            with self.subTest(cause=type(cause).__name__):
                self.assertIn(expected, self.error_message(error=urllib.error.URLError(cause)))
        self.assertIn("timed out", self.error_message(error=TimeoutError(PRIVATE)))

    def test_empty_value_and_blank_link_report_monthly_unavailability(self):
        for payload in ({"value": []}, {"value": [{"Link": ""}]},
                        {"value": [{"Link": "  "}]}, {"value": [{"Link": None}]}):
            with self.subTest(payload=payload):
                self.assertIn("unavailable", self.error_message(body=json.dumps(payload).encode()))

    def test_malformed_json_and_unexpected_schema_are_separate(self):
        self.assertIn("malformed json", self.error_message(body=PRIVATE.encode()))
        for payload in ([], {"value": PRIVATE}, {"value": [{}]}, {"value": [1]},
                        {"value": [{"Link": 123}]}, {"value": [{}, {}]}):
            with self.subTest(payload=payload):
                self.assertIn("schema", self.error_message(body=json.dumps(payload).encode()))
        self.assertIn("https", self.error_message(body=json.dumps({"value": [{"Link": "http://fixture.invalid/"}]}).encode()))

    def test_valid_temporary_link_is_returned_without_printing_it(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            link = acquisition._signed_link(Reply(json.dumps({"value": [{"Link": SIGNED}]}).encode()),
                                            "Train", "202609", SECRET)
        self.assertEqual(link, SIGNED)
        self.assertNotIn(SIGNED, output.getvalue())
        self.assertNotIn(SECRET, output.getvalue())

    def test_progress_precedes_network_and_errors_remain_safe_at_cli_boundary(self):
        output = io.StringIO()
        def assert_progress_already_visible():
            self.assertIn("Requesting PV/ODTrain 2026-08", output.getvalue())
        error = urllib.error.HTTPError(SIGNED, 401, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
        reply = Reply(error=error, before_open=assert_progress_already_visible)
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = acquisition.main(["--download"], environ={"LTA_ACCOUNT_KEY": SECRET},
                                    root=Path(folder), opener=reply)
            self.assertEqual(list(Path(folder).iterdir()), [])
        self.assertEqual(code, 2)
        self.assertIn("HTTP 401", output.getvalue())
        self.assertNotIn(SECRET, output.getvalue())
        self.assertNotIn(SIGNED, output.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
