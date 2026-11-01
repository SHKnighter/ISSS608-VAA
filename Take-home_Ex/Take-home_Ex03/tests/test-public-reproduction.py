"""Regression: a source-only checkout reaches the data gate without private workflow files."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SourceOnlyCheckout(unittest.TestCase):
    def test_catalog_survives_a_source_only_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            checkout = Path(folder)
            (checkout/'R').mkdir()
            shutil.copy2(ROOT/'R/acquire-public.py',checkout/'R/acquire-public.py')
            metadata=ROOT/'data/metadata'
            if metadata.exists(): shutil.copytree(metadata,checkout/'data/metadata')
            result=subprocess.run([sys.executable,str(checkout/'R/acquire-public.py'),'--verify'],capture_output=True,text=True)
            self.assertEqual(result.returncode,1)
            self.assertIn('No acquisition.json yet',result.stderr)
            self.assertNotIn('Missing public-source-catalog.json',result.stderr)

if __name__=='__main__': unittest.main()
