"""Publication checks use disposable Git repositories and never access devices."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PublicationAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mtp-audit-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / 'Vendor', self.root / 'Vendor')
        (self.root / 'Scripts').mkdir()
        shutil.copy2(ROOT / 'Scripts/audit-publication.py', self.root / 'Scripts/audit-publication.py')
        shutil.copy2(ROOT / '.gitignore', self.root / '.gitignore')
        (self.root / 'README.md').write_text('# Fixture\n')
        self.git('init', '-q')
        self.git('add', '.')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True, capture_output=True)

    def audit(self, *args):
        return subprocess.run([sys.executable, str(self.root / 'Scripts/audit-publication.py'), *args],
                              capture_output=True, text=True)

    def test_clean_source_and_vendor_are_accepted(self):
        result = self.audit('--staged')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ignored_local_environment_is_excluded(self):
        (self.root / '.env').write_text('LOCAL_ONLY=value\n')
        self.assertEqual(self.audit().returncode, 0)

    def test_forced_tracked_diagnostics_are_rejected(self):
        (self.root / 'private.log').write_text('device data\n')
        self.git('add', '-f', 'private.log')
        result = self.audit('--staged')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('private.log', result.stderr)

    def test_staged_secret_is_checked_even_if_working_copy_is_clean(self):
        token = 'gh' + 'p_' + 'A' * 36
        (self.root / 'README.md').write_text(token)
        self.git('add', 'README.md')
        (self.root / 'README.md').write_text('# Redacted working copy\n')
        result = self.audit('--staged')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(token, result.stdout + result.stderr)
        self.assertEqual(self.audit().returncode, 0)

    def test_modified_vendored_binary_is_rejected(self):
        library = self.root / 'Vendor/lib/libmtp.9.dylib'
        library.write_bytes(library.read_bytes() + b'changed')
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum', result.stderr)

    def test_personal_absolute_paths_are_rejected(self):
        home_path = '/'.join(['', 'Users', 'fixture', 'workspace'])
        (self.root / 'README.md').write_text(home_path)
        result = self.audit()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('home path', result.stderr)


if __name__ == '__main__':
    unittest.main()
