#!/usr/bin/env python3
"""Exercise pin validation only on temporary copies, never the source tree."""
import importlib.util
import pathlib
import shutil
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pins', ROOT/'scripts/verify-patch-pins.py')
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)


class PatchPins(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        shutil.copy(ROOT/'build.sh', self.root/'build.sh')
        shutil.copytree(ROOT/'patches', self.root/'patches')
        self.build = self.root/'build.sh'
        self.patch = self.root/'patches/forge-diag-menu.patch'

    def edit(self, old, new):
        self.build.write_text(self.build.read_text().replace(old, new))

    def test_clean(self):
        self.assertEqual(pins.verify(self.root), 6)

    def test_each_patch_tamper(self):
        for path in (self.root/'patches').glob('*.patch'):
            original = path.read_bytes()
            path.write_bytes(original + b'\n')
            with self.subTest(path=path.name), self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                pins.verify(self.root)
            path.write_bytes(original)

    def test_missing_patch(self):
        self.patch.unlink()
        with self.assertRaisesRegex(ValueError, 'regular file'):
            pins.verify(self.root)

    def test_duplicate_declaration(self):
        self.build.write_text(self.build.read_text()+'\nFORGE_PATCH6="patches/forge-diag-menu.patch"\n')
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            pins.verify(self.root)

    def test_missing_declaration(self):
        self.edit('FORGE_PATCH6=', 'OLD_PATCH6=')
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            pins.verify(self.root)

    def test_malformed_hash(self):
        self.edit('EXPECTED_PATCH6_SHA256="', 'EXPECTED_PATCH6_SHA256="z')
        with self.assertRaisesRegex(ValueError, 'invalid SHA256'):
            pins.verify(self.root)

    def test_dynamic_declaration(self):
        self.edit('FORGE_PATCH6="patches/forge-diag-menu.patch"', 'FORGE_PATCH6=$(exit 9)')
        with self.assertRaisesRegex(ValueError, 'unsupported declaration'):
            pins.verify(self.root)

    def test_parent_path(self):
        self.edit('patches/forge-diag-menu.patch', '../forge-diag-menu.patch')
        with self.assertRaisesRegex(ValueError, 'invalid patch path'):
            pins.verify(self.root)

    def test_symlink(self):
        self.patch.unlink()
        self.patch.symlink_to(self.root/'patches/forge-diag-generator.patch')
        with self.assertRaisesRegex(ValueError, 'regular file'):
            pins.verify(self.root)


if __name__ == '__main__':
    unittest.main()
