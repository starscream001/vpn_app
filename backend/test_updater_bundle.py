import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location('linux_update',Path(__file__).parents[1]/'native/updater/linux_update.py')
updater=importlib.util.module_from_spec(spec);spec.loader.exec_module(updater)
class UpdaterArchiveTests(unittest.TestCase):
    def archive(self,folder,extra=None,complete=True):
        p=Path(folder)/'release.zip'
        with zipfile.ZipFile(p,'w') as z:
            if complete:
                for name in ('foxway','sing-box','amneziawg-go','awg','awg-quick','foxway-guard.py'):z.writestr(name,b'fixture')
            if extra:z.writestr(extra,b'unsafe')
        return p,hashlib.sha256(p.read_bytes()).hexdigest()
    def test_valid_complete_bundle(self):
        with tempfile.TemporaryDirectory() as folder:
            p,digest=self.archive(folder);self.assertTrue(updater.validate(p,digest))
    def test_checksum_mismatch_rejected_before_install(self):
        with tempfile.TemporaryDirectory() as folder:
            p,_=self.archive(folder)
            with self.assertRaises(ValueError):updater.validate(p,'0'*64)
    def test_traversal_and_absolute_paths_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ('../escape','/etc/test','C:\\escape','dir\\escape'):
                p,digest=self.archive(folder,name)
                with self.assertRaises(ValueError):updater.validate(p,digest)
    def test_incomplete_bundle_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p,digest=self.archive(folder,complete=False)
            with self.assertRaises(ValueError):updater.validate(p,digest)
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p,_=self.archive(folder)
            with zipfile.ZipFile(p,'a') as z:
                e=zipfile.ZipInfo('link');e.external_attr=0o120777<<16;z.writestr(e,'/etc')
            with self.assertRaises(ValueError):updater.validate(p,hashlib.sha256(p.read_bytes()).hexdigest())
