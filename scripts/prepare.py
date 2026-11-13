#!/usr/bin/env python3
"""Materialize pinned upstream in an expendable runtime; keep upstream clean."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
UP = ROOT/'upstream/openfire'
GAME = ROOT/'.runtime/game'

def prepare(patched=False):
    lock=json.loads((ROOT/'upstream.lock.json').read_text())
    sha=subprocess.check_output(['git','-C',str(UP),'rev-parse','HEAD'],text=True).strip()
    if sha != lock['commit']: raise RuntimeError(f'Upstream drift: {sha}')
    if subprocess.check_output(['git','-C',str(UP),'status','--porcelain','--untracked-files=no'],text=True).strip():
        raise RuntimeError('Tracked upstream changes detected')
    # Preserve generated imports between reruns, copy only tracked source.
    paths=subprocess.check_output(['git','-C',str(UP),'ls-files','-z']).decode().split('\0')
    for name in filter(None,paths):
        dest=GAME/name; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(UP/name,dest)
    changes=[]
    # Upstream release workflow uses this exact optional-addon omission when libs absent.
    manifest=GAME/'addons/nobodywho/nobodywho.gdextension'
    if manifest.exists():
        manifest.unlink(); changes.append({'path':str(manifest.relative_to(GAME)),'reason':'optional native LLM libraries absent; same fallback as upstream release workflow'})
    # Isolate user:// from the real game's settings/save directory, inside disposable runtime.
    cfg=GAME/'project.godot'; s=cfg.read_text(); s=s.replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+"FPSCombatQA/20261113"+'"')
    cfg.write_text(s); changes.append({'path':'project.godot','reason':'dedicated FPSCombatQA/20261113 user data directory; gameplay settings unchanged'})
    if patched:
        for patch in sorted((ROOT/'patches').glob('*.patch')):
            subprocess.run(['git','apply','--unsafe-paths','--directory='+str(GAME),str(patch)],check=True,cwd='/')
            changes.append({'patch':patch.name,'sha256':hashlib.sha256(patch.read_bytes()).hexdigest()})
    qa=GAME/'tests/qa'
    if qa.exists(): shutil.rmtree(qa)  # discard previous injected guard fixtures
    if (ROOT/'tests').exists(): shutil.copytree(ROOT/'tests',qa)
    (ROOT/'.runtime/preparation.json').write_text(json.dumps({'upstream_commit':sha,'patched':patched,'changes':changes},ensure_ascii=False,indent=2)+'\n')
    print(GAME)
    return GAME

if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--patched',action='store_true');args=a.parse_args();prepare(args.patched)
