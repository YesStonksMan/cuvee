#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Assemble a relocatable, self-contained Mac release. Never package a user's runtime wholesale."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
MACHO = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
SYSTEM = ('/usr/lib/', '/System/Library/')


def run(*args):
    try:
        return subprocess.check_output([str(x) for x in args], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        print(error.output, flush=True)
        raise


def is_macho(path):
    if path.is_symlink() or not path.is_file():
        return False
    with path.open('rb') as f:
        return f.read(4) in MACHO


def dependencies(path):
    return [line.strip().split(' (compatibility')[0] for line in run('otool', '-L', path).splitlines()[1:] if line.startswith('\t')]


def rpaths(path):
    return re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.*?) \(offset', run('otool', '-l', path))


def stage_runtime(source, dest):
    # Allowlist: no Bottles, Downloads, logs, credentials, optional CrossOver/Apple graphics binaries, or tools.
    for name in ('wine', 'wineserver'):
        target = dest / 'bin' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / 'bin' / name, target)
    for name in ('wine', 'dxmt'):
        shutil.copytree(source / 'lib' / name, dest / 'lib' / name, symlinks=True)
    for path in (source / 'lib').glob('*.dylib'):
        if path.name.startswith(('libgmp.', 'libnettle.', 'libhogweed.', 'libgnutls.', 'libfreetype.')):
            shutil.copy2(path, dest / 'lib' / path.name, follow_symlinks=False)
    shutil.copytree(source / 'share' / 'wine', dest / 'share' / 'wine', symlinks=True)
    validate_tree(dest)


def validate_tree(root):
    for path in root.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'escaping symlink: {path}')
        if path.name in {'Bottles', 'Downloads', 'libMoltenVK.dylib', 'libmetalirconverter.dylib', 'vkd3d-proton'}:
            raise ValueError(f'non-distributable or personal content: {path}')


def relocate(root):
    binaries = [p for p in root.rglob('*') if is_macho(p)]
    for binary in binaries:
        ids = run('otool', '-D', binary).splitlines()[1:]
        identity = ids[0].strip() if ids else None
        changes = []
        for dep in dependencies(binary):
            if dep == identity or dep.startswith(SYSTEM):
                continue
            # Resolve relative references first; old absolute build paths map to a bundled basename.
            candidate = binary.parent / dep.removeprefix('@loader_path/') if dep.startswith('@loader_path/') else None
            if candidate is None or not candidate.exists():
                matches = [p for p in root.rglob(Path(dep).name) if p.is_file()]
                # Symlinks and their target at the same resolved path are one library.
                matches = list({p.resolve(): p for p in matches}.values())
                if len(matches) != 1:
                    raise ValueError(f'unresolved dependency {dep} in {binary}')
                candidate = matches[0]
            relative = '@loader_path/' + os.path.relpath(candidate, binary.parent)
            if relative != dep:
                changes += ['-change', dep, relative]
        if identity:
            changes += ['-id', '@rpath/' + binary.name]
        for old in rpaths(binary):
            if old.startswith('/') and not old.startswith(SYSTEM):
                changes += ['-delete_rpath', old]
        if changes:
            run('install_name_tool', *changes, binary)
    audit(root)
    for binary in binaries:
        run('codesign', '--force', '--sign', '-', binary)
    return len(binaries)


def audit(root):
    validate_tree(root)
    for binary in (p for p in root.rglob('*') if is_macho(p)):
        ids = run('otool', '-D', binary).splitlines()[1:]
        identity = ids[0].strip() if ids else None
        for dep in dependencies(binary):
            if dep == identity or dep.startswith(SYSTEM):
                continue
            if not dep.startswith('@loader_path/'):
                raise ValueError(f'non-relocatable dependency {dep} in {binary}')
            target = (binary.parent / dep[len('@loader_path/'):]).resolve()
            if not target.is_relative_to(root.resolve()) or not target.is_file():
                raise ValueError(f'dependency outside package: {dep} in {binary}')
        for rpath in rpaths(binary):
            if rpath.startswith('/') and not rpath.startswith(SYSTEM):
                raise ValueError(f'absolute build rpath: {rpath}')


def source_filter(info):
    if any(part in {'.git', '__pycache__', '.DS_Store'} for part in Path(info.name).parts):
        return None
    info.uid = info.gid = 0
    info.uname = info.gname = 'root'
    return info


def sources_and_licenses(args, resources, output):
    if run('git', '-C', args.dxmt_source, 'rev-parse', 'HEAD').strip() != '589adb780354b461645b29999cefaf533594ee99':
        raise ValueError('DXMT source must be v0.80')
    if any(line.startswith(('-', '+', 'U')) for line in run('git', '-C', args.dxmt_source, 'submodule', 'status', '--recursive').splitlines()):
        raise ValueError('DXMT source submodules must match the pinned revisions')
    licenses = resources / 'Licenses'
    licenses.mkdir()
    components = {
        'Wine': args.sources / 'sources/wine',
        'GMP': args.sources / 'sources/gnutls/gmp',
        'GnuTLS': args.sources / 'sources/gnutls/gnutls',
        'FreeType': args.sources / 'sources/freetype',
        'Nettle': args.sources / 'nettle-3.10',
        'DXMT': args.dxmt_source,
    }
    # Take the actual patched source trees used for Wine and dependencies, including bundled subprojects.
    with tarfile.open(output, 'w:gz', compresslevel=3) as archive:
        files = run('git', '-C', ROOT, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split('\0')
        for name in files:
            if name and (name in {'cuvee', 'LICENSE', 'README.md', '.gitignore', 'fetch-sources.sh',
                                 'build-deps.sh', 'build-wine.sh', 'build-vkd3d-proton.sh', 'VERSION'}
                         or Path(name).parts[0] in {'launcher', 'patches', 'packaging', 'branding', 'tests', '.github'}):
                archive.add(ROOT / name, arcname='cuvee/' + name, filter=source_filter)
        for name, path in components.items():
            if not path.is_dir():
                raise ValueError(f'missing source: {path}')
            archive.add(path, arcname='upstream/' + name, filter=source_filter)
            for file in path.rglob('*'):
                if file.is_file() and not file.is_symlink() and file.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')):
                    target = licenses / name / file.relative_to(path)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(file, target)
        if hashlib.sha256(args.gecko_source.read_bytes()).hexdigest() != 'bf31b6619570ce289f07298bdd670081635cd12104010050f06c16e44ccd153f':
            raise ValueError('unexpected Wine Gecko 2.47.4 source checksum')
        archive.add(args.gecko_source, arcname='upstream/wine-gecko-2.47.4-src.tar.xz', filter=source_filter)
    shutil.copy2(ROOT / 'LICENSE', licenses / 'Cuvee-LGPL-2.1.txt')
    with tarfile.open(args.gecko_source) as archive:
        for name in ('wine-gecko-2.47.4/LICENSE', 'wine-gecko-2.47.4/toolkit/content/license.html'):
            f = archive.extractfile(name)
            if f:
                (licenses / ('Gecko-' + Path(name).name)).write_bytes(f.read())
    shutil.copy2(ROOT / 'packaging/THIRD-PARTY-NOTICES.txt', resources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True, help='built dist/ (never a user-data folder)')
    parser.add_argument('--sources', type=Path, required=True, help='src/ containing actual patched build sources')
    parser.add_argument('--dxmt-source', type=Path, required=True, help='DXMT v0.80 source with submodules')
    parser.add_argument('--gecko-source', type=Path, required=True, help='official wine-gecko-2.47.4-src.tar.xz')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', default=(ROOT / 'VERSION').read_text().strip())
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        parser.error('version must be major.minor.patch')
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cuvee-release-') as temp:
        work = Path(temp)
        image = work / 'image'
        image.mkdir()
        app = image / 'Cuvee.app'
        print('Building app…', flush=True)
        print(run('bash', ROOT / 'launcher/build.sh', '--output', app, '--no-install', '--ad-hoc'), flush=True)
        contents = app / 'Contents'
        resources = contents / 'Resources'
        runtime = resources / 'runtime'
        stage_runtime(args.runtime, runtime / 'dist')
        shutil.copy2(ROOT / 'cuvee', runtime / 'cuvee')
        print('Relocating engine…', flush=True)
        count = relocate(runtime / 'dist')
        info_path = contents / 'Info.plist'
        with info_path.open('rb') as f:
            info = plistlib.load(f)
        info.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.version,
                    LSMinimumSystemVersion='15.0', LSArchitecturePriority=['arm64'])
        with info_path.open('wb') as f:
            plistlib.dump(info, f)
        print('Archiving corresponding sources and licenses…', flush=True)
        sources = args.output / f'Cuvee-{args.version}-sources.tar.gz'
        sources_and_licenses(args, resources, sources)
        metadata = {'version': args.version, 'minimum_macos': '15.0', 'architecture': 'arm64',
                    'engine_architecture': 'x86_64 (Rosetta 2)', 'graphics': ['DXMT 0.80', 'OpenGL'],
                    'notarized': False, 'signing': 'ad-hoc', 'relocated_mach_o_files': count,
                    'sources': sources.name, 'source_sha256': hashlib.sha256(sources.read_bytes()).hexdigest()}
        (resources / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
        run('xattr', '-cr', app)
        run('codesign', '--force', '--sign', '-', app)
        run('codesign', '--verify', '--deep', '--strict', app)
        audit(runtime / 'dist')
        shutil.copy2(ROOT / 'packaging/INSTALL.txt', image / 'INSTALL.txt')
        (image / 'Applications').symlink_to('/Applications')
        package = work / 'Cuvee-component.pkg'
        # Explicitly disable relocation: an older app elsewhere must not redirect this install.
        component = work / 'component.plist'
        component.write_bytes(plistlib.dumps([{'RootRelativeBundlePath': 'Cuvee.app',
                                              'BundleIsRelocatable': False, 'BundleIsVersionChecked': True,
                                              'BundleHasStrictIdentifier': True, 'BundleOverwriteAction': 'upgrade'}]))
        payload = work / 'payload'
        payload.mkdir()
        app.rename(payload / 'Cuvee.app')
        run('pkgbuild', '--root', payload, '--component-plist', component,
            '--install-location', '/Applications', '--identifier', 'io.github.yesstonksman.cuvee',
            '--version', args.version, package)
        (payload / 'Cuvee.app').rename(app)
        distribution = work / 'Distribution.xml'
        distribution.write_text(f'''<?xml version="1.0"?>
<installer-gui-script minSpecVersion="2">
<title>Cuvee {args.version}</title>
<welcome file="INSTALL.txt" mime-type="text/plain"/>
<options customize="never" require-scripts="false" hostArchitectures="arm64"/>
<volume-check script="true"><allowed-os-versions><os-version min="15.0"/></allowed-os-versions></volume-check>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<choices-outline><line choice="cuvee"/></choices-outline>
<choice id="cuvee" title="Cuvee" visible="false"><pkg-ref id="io.github.yesstonksman.cuvee"/></choice>
<pkg-ref id="io.github.yesstonksman.cuvee" version="{args.version}">Cuvee-component.pkg</pkg-ref>
</installer-gui-script>''')
        base = f'Cuvee-{args.version}-macOS-AppleSilicon'
        print('Creating installer…', flush=True)
        print(run('productbuild', '--distribution', distribution, '--resources', image, '--package-path', work,
                  args.output / (base + '.pkg')), flush=True)
        expanded = work / 'verify-pkg'
        run('pkgutil', '--expand-full', args.output / (base + '.pkg'), expanded)
        run('codesign', '--verify', '--deep', '--strict', expanded / 'Cuvee-component.pkg/Payload/Cuvee.app')
        print('Creating disk image…', flush=True)
        print(run('hdiutil', 'create', '-volname', f'Cuvee {args.version}', '-srcfolder', image,
                  '-format', 'UDZO', '-ov', args.output / (base + '.dmg')), flush=True)
        run('hdiutil', 'verify', args.output / (base + '.dmg'))
        # Deliver containers only: File Provider can re-tag loose .app bundles in Documents
        # with FinderInfo immediately after signing. The verified app stays inside PKG/DMG.
        (args.output / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
        shutil.copy2(ROOT / 'packaging/INSTALL.txt', args.output / 'INSTALL.txt')
        paths = [sources, args.output / (base + '.pkg'), args.output / (base + '.dmg')]
        (args.output / 'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in paths))
        print(f'Release ready in {args.output}', flush=True)


if __name__ == '__main__':
    main()
