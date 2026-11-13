#!/usr/bin/env python3
"""Install checksum-pinned official Godot; no pip dependencies or export templates."""
import hashlib, json, os, platform, subprocess, sys, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def godot_path():
    return ROOT/'.runtime'/('Godot.app/Contents/MacOS/Godot' if sys.platform=='darwin' else 'Godot_v4.6-stable_linux.x86_64')

def bootstrap():
    up=ROOT/'upstream/openfire';lock=json.loads((ROOT/'upstream.lock.json').read_text())
    if not (up/'.git').exists():
        # submodule init preserves a fixed gitlink when this QA repo was cloned.
        subprocess.run(['git','submodule','update','--init','--recursive'],cwd=ROOT,check=True)
    if not (up/'.git').exists(): raise RuntimeError('Clone with --recurse-submodules; upstream is required')
    sha=subprocess.check_output(['git','-C',str(up),'rev-parse','HEAD'],text=True).strip()
    if sha!=lock['commit']:raise RuntimeError('Upstream SHA differs from lock')
    binary=godot_path()
    if not binary.exists():
        if sys.platform=='darwin': name='Godot_v4.6-stable_macos.universal.zip'
        elif sys.platform.startswith('linux') and platform.machine() in ['x86_64','AMD64']:name='Godot_v4.6-stable_linux.x86_64.zip'
        else:raise RuntimeError('Bootstrap supports macOS universal and Linux x86_64 only')
        asset=json.loads((ROOT/'engine.lock.json').read_text())['assets'][name]
        archive=ROOT/'.runtime'/name;archive.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['curl','--fail','--location','--retry','2','--max-time','600',asset['url'],'--output',str(archive)],check=True)
        digest=hashlib.file_digest(archive.open('rb'),'sha512').hexdigest()
        if digest!=asset['sha512']:raise RuntimeError('Official Godot archive checksum mismatch')
        with zipfile.ZipFile(archive) as z:z.extractall(ROOT/'.runtime')
        binary.chmod(0o755)
    # Portable editor storage. Runtime user data uses the named QA-only directory.
    (ROOT/'.runtime/_sc_').touch()
    if sys.platform=='darwin':(ROOT/'.runtime/Godot.app/Contents/_sc_').touch()
    version=subprocess.check_output([str(binary),'--version'],text=True).strip()
    expected=json.loads((ROOT/'engine.lock.json').read_text())['version']
    if version!=expected:raise RuntimeError(f'Engine mismatch: expected {expected}, got {version}')
    return binary

if __name__=='__main__':print(bootstrap())
