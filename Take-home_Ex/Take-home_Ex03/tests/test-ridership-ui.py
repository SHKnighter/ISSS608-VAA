"""Offline behavior checks for local key entry/download feedback."""
import importlib.util
import io
from pathlib import Path
import queue
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT/'R/ridership-ui.py'
ui = None
if SCRIPT.exists():
    spec=importlib.util.spec_from_file_location('ridership_ui',SCRIPT)
    ui=importlib.util.module_from_spec(spec);spec.loader.exec_module(ui)

class FeedbackTests(unittest.TestCase):
    def test_empty_entry_cannot_start_a_download(self):
        self.assertIsNotNone(ui,'No visible masked-input interface yet')
        events=queue.Queue()
        with tempfile.TemporaryDirectory() as folder:
            ui.perform_download('   ',Path(folder),events)
            self.assertEqual(list(Path(folder).iterdir()),[])
        result=list(events.queue)
        self.assertEqual(result[-1][0],'error')

    def test_safe_stage_and_failure_feedback_never_echo_key(self):
        self.assertIsNotNone(ui,'No visible masked-input interface yet')
        events=queue.Queue(); secret='fixture-not-a-real-key'
        def failed(root,key):
            print('Requesting ODTrain 202608')
            raise ui.backend.AcquisitionError('HTTP 401: API key rejected')
        ui.perform_download(secret,ROOT,events,acquire_fn=failed)
        result=list(events.queue)
        self.assertTrue(any('Requesting ODTrain' in msg for kind,msg in result))
        self.assertEqual(result[-1],('error','HTTP 401: API key rejected'))
        self.assertNotIn(secret,str(result))

    def test_success_and_unexpected_failure_are_reported_without_secret(self):
        self.assertIsNotNone(ui,'No visible masked-input interface yet')
        events=queue.Queue()
        ui.perform_download('fixture',ROOT,events,acquire_fn=lambda root,key: None)
        self.assertEqual(list(events.queue)[-1][0],'done')
        def bad(root,key): raise RuntimeError(key)
        events=queue.Queue(); ui.perform_download('do-not-show',ROOT,events,acquire_fn=bad)
        self.assertEqual(list(events.queue)[-1][0],'error')
        self.assertNotIn('do-not-show',str(list(events.queue)))

if __name__=='__main__': unittest.main(verbosity=2)
