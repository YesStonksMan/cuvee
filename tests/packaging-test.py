#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Exercise release safety and real Mach-O relocation using isolated fixtures."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('package', Path(__file__).resolve().parents[1] / 'packaging/package.py')
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cuvee packaging test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_rejects_escaping_symlink(self):
        (self.root / 'escape').symlink_to('/Users')
        with self.assertRaisesRegex(ValueError, 'escaping symlink'):
            pkg.validate_tree(self.root)

    def test_rejects_personal_and_restricted_files(self):
        for name in ('Bottles', 'Downloads', 'libMoltenVK.dylib', 'libmetalirconverter.dylib', 'vkd3d-proton'):
            path = self.root / name
            path.touch()
            with self.assertRaises(ValueError):
                pkg.validate_tree(self.root)
            path.unlink()

    def test_allowlist_excludes_private_and_optional_payloads(self):
        source = self.root / 'source'
        for name in ('bin/wine', 'bin/wineserver', 'bin/winegcc', 'lib/wine/x.so', 'lib/dxmt/x.so',
                     'lib/libgnutls.30.dylib', 'share/wine/wine.inf', 'lib/libMoltenVK.dylib',
                     'lib/vkd3d-proton/private', 'Bottles/Steam/account', 'Downloads/installer.exe'):
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        dest = self.root / 'packaged'
        pkg.stage_runtime(source, dest)
        self.assertTrue((dest / 'bin/wine').is_file())
        self.assertTrue((dest / 'lib/libgnutls.30.dylib').is_file())
        for name in ('bin/winegcc', 'lib/libMoltenVK.dylib', 'lib/vkd3d-proton', 'Bottles', 'Downloads'):
            self.assertFalse((dest / name).exists())

    def compile_pair(self):
        original = self.root / 'developer machine'
        original.mkdir()
        c = original / 'a.c'
        c.write_text('int answer(void) { return 42; }\n')
        library = original / 'libanswer.dylib'
        pkg.run('clang', '-dynamiclib', c, '-install_name', library, '-o', library)
        c.write_text('extern int answer(void); int main(void) { return answer() == 42 ? 0 : 1; }\n')
        binary = original / 'probe'
        pkg.run('clang', c, library, '-Wl,-rpath,' + str(original), '-o', binary)
        bundled = self.root / 'app relocated/dist'
        (bundled / 'bin').mkdir(parents=True)
        (bundled / 'lib').mkdir()
        shutil.copy2(binary, bundled / 'bin/probe')
        shutil.copy2(library, bundled / 'lib/libanswer.dylib')
        return original, bundled

    def test_relocation_runs_with_original_library_removed(self):
        original, bundled = self.compile_pair()
        with self.assertRaisesRegex(ValueError, 'non-relocatable dependency'):
            pkg.audit(bundled)
        self.assertEqual(pkg.relocate(bundled), 2)
        shutil.rmtree(original)
        self.assertEqual(subprocess.run([bundled / 'bin/probe']).returncode, 0)
        pkg.audit(bundled)
        for p in (bundled / 'bin/probe', bundled / 'lib/libanswer.dylib'):
            pkg.run('codesign', '--verify', '--strict', p)

    def test_missing_dependency_fails_closed(self):
        _, bundled = self.compile_pair()
        (bundled / 'lib/libanswer.dylib').unlink()
        with self.assertRaisesRegex(ValueError, 'unresolved dependency'):
            pkg.relocate(bundled)

    def test_cli_defaults_to_dxmt_without_moltenvk(self):
        runtime = self.root / 'runtime'
        (runtime / 'dist/bin').mkdir(parents=True)
        (runtime / 'dist/lib/dxmt').mkdir(parents=True)
        wine = runtime / 'dist/bin/wine'
        wine.write_text('#!/bin/bash\nexit 0\n')
        wine.chmod(0o755)
        shutil.copy2(pkg.ROOT / 'cuvee', runtime / 'cuvee')
        bottles = self.root / 'test bottles'
        (bottles / 'test/drive_c').mkdir(parents=True)
        env = dict(os.environ, CUVEE_BOTTLES=str(bottles))
        output = subprocess.check_output(['bash', runtime / 'cuvee', 'settings', 'test'], env=env, text=True)
        self.assertIn('graphics=dxmt', output)
        (runtime / 'dist/lib/libMoltenVK.dylib').touch()
        output = subprocess.check_output(['bash', runtime / 'cuvee', 'settings', 'test'], env=env, text=True)
        self.assertIn('graphics=vulkan', output)


if __name__ == '__main__':
    unittest.main(verbosity=2)
