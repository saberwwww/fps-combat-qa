#!/usr/bin/env python3
"""Real engine failures test the runner guards; these are infrastructure experiments."""
import json
from pathlib import Path
from bootstrap import bootstrap
from capture import capture
from prepare import ROOT, prepare
from run import validate_process, load_report

def main():
    godot=bootstrap();game=prepare(True)
    out=ROOT/'evidence/guards'
    if out.exists():raise RuntimeError('Guard evidence already exists; archive or choose another run directory')
    out.mkdir(parents=True)
    fixtures={
        'runtime': 'extends SceneTree\nfunc _initialize():\n\tcreate_timer(0.2).timeout.connect(func(): quit(0))\n\tcall_deferred("fault")\nfunc fault():\n\tvar d: Dictionary = {}\n\tprint(d["missing"])\n',
        'syntax': 'extends SceneTree\nfunc _initialize(\n',
        'timeout': 'extends SceneTree\n',
    }
    results=[]
    for kind,source in fixtures.items():
        script=game/'tests/qa'/('guard_'+kind+'.gd');script.write_text(source)
        r=capture([str(godot),'--headless','--path',str(game),'--script','res://tests/qa/'+script.name],out/kind,2)
        detected=validate_process(r,out/(kind+'.log'))
        good=bool(detected)
        if kind=='runtime':good=good and r['exit_code']==0 and any('SCRIPT ERROR' in x for x in detected)
        if kind=='timeout':good=good and r['timed_out']
        results.append({'fault':kind,'detected':good,'issues':detected,'exit_code':r['exit_code'],'timed_out':r['timed_out']})
    _,issues=load_report(out/'nonexistent-report.json')
    results.append({'fault':'missing report','detected':bool(issues),'issues':issues})
    (out/'verification.json').write_text(json.dumps(results,indent=2)+'\n')
    return 0 if all(r['detected'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
