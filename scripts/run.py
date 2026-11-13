#!/usr/bin/env python3
"""Single regression gate: exit + deadline + engine diagnostics + exact case manifest."""
import argparse, datetime, hashlib, json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
from bootstrap import bootstrap
from capture import capture
from network_run import run_network
from prepare import ROOT, prepare
COMBAT={f'W{i:02d}' for i in range(1,17)}|{f'D{i:02d}' for i in range(1,10)}
NETWORK={f'N{i:02d}' for i in range(1,8)}

def diagnostics(log):
    return [line for line in Path(log).read_text(errors='replace').splitlines()
            if re.match(r'^\s*(?:SCRIPT ERROR:|ERROR:)',line)]

def validate_process(meta, log):
    issues=[]
    if meta['timed_out']:issues.append('timeout')
    if meta['exit_code']!=0:issues.append(f"exit={meta['exit_code']}")
    issues+=diagnostics(log)
    return issues

def load_report(path, expected_role=None):
    p=Path(path)
    try:
        r=json.loads(p.read_text())
        if expected_role and r.get('role')!=expected_role:raise ValueError('role mismatch')
        rows=r['results']
        if r['checks']!=len(rows):raise ValueError('check count mismatch')
        if r['failed']!=sum(x['passed'] is not True for x in rows):raise ValueError('failure count mismatch')
        if not all(isinstance(x['id'],str) and type(x['passed']) is bool and 'expected' in x and 'actual' in x for x in rows):raise ValueError('malformed assertion')
        return rows,[]
    except (OSError,ValueError,KeyError,TypeError) as e:return [],[f'{p.name}: missing/invalid report: {e}']

def junit(rows, issues, output):
    suite=ET.Element('testsuite',name='OpenFire QA',tests=str(len(rows)+len(issues)),failures=str(sum(not x['passed'] for x in rows)+len(issues)))
    for row in rows:
        c=ET.SubElement(suite,'testcase',name=row['id'],classname='OpenFire')
        detail=json.dumps({'expected':row['expected'],'actual':row['actual']},ensure_ascii=False)
        if not row['passed']:ET.SubElement(c,'failure',message='game rule assertion failed').text=detail
        else:ET.SubElement(c,'system-out').text=detail
    for i,issue in enumerate(issues):
        c=ET.SubElement(suite,'testcase',name=f'INFRA-{i+1}',classname='Harness')
        ET.SubElement(c,'failure',message=issue).text=issue
    ET.ElementTree(suite).write(output,encoding='utf-8',xml_declaration=True)

def main():
    a=argparse.ArgumentParser();a.add_argument('--suite',choices=['all','combat','network'],default='all')
    a.add_argument('--out',type=Path);a.add_argument('--inject-failure',action='store_true');a.add_argument('--unpatched',action='store_true')
    args=a.parse_args()
    if args.inject_failure and args.suite=="network":a.error("--inject-failure requires combat or all")
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    out=(args.out or ROOT/'evidence/runs'/stamp).resolve()
    if out.exists() and any(out.iterdir()):raise RuntimeError('Refusing to overwrite previous evidence')
    out.mkdir(parents=True,exist_ok=True)
    rows=[];issues=[];expected=set();provenance={}
    try:
        godot=bootstrap();game=prepare(not args.unpatched)
        provenance=json.loads((ROOT/'.runtime/preparation.json').read_text())
        provenance['engine']=json.loads((ROOT/'engine.lock.json').read_text())['version']
        provenance['source_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['scripts','tests','patches'] for p in sorted((ROOT/folder).rglob('*')) if p.is_file() and '__pycache__' not in str(p)}
        provenance['mutation']='consume two bullets instead of one (controlled injection)' if args.inject_failure else None
        if args.inject_failure:
            path=game/'scripts/player/weapon_manager.gd';s=path.read_text();old='a["mag"] -= 1'
            if s.count(old)!=1:raise RuntimeError('Mutation target drift')
            path.write_text(s.replace(old,'a["mag"] -= 2'))
        (out/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
        meta=capture([str(godot),'--headless','--path',str(game),'--import'],out/'import-process',180)
        issues+=validate_process(meta,out/'import-process.log')
        if issues:raise RuntimeError('Import failed; scene tests not started')
        if args.suite in ['all','combat']:
            expected|=COMBAT
            cmd=[str(godot),'--headless','--path',str(game),'res://tests/qa/combat.tscn','--',f'--report={out/"combat-report.json"}']
            meta=capture(cmd,out/'combat-process',60);issues+=validate_process(meta,out/'combat-process.log')
            found,errors=load_report(out/'combat-report.json');rows+=found;issues+=errors
        if args.suite in ['all','network']:
            expected|=NETWORK
            for scenario in ['combat','server-drop']:
                folder=out/('network-'+scenario)
                processes=run_network(godot,game,folder,scenario)
                if len(processes)!=2:issues.append(f'{scenario}: host failed to become ready')
                for role in ['host','client']:
                    m=folder/(role+'-process.json')
                    if m.exists():issues+=validate_process(json.loads(m.read_text()),folder/(role+'-process.log'))
                    else:issues.append(f'{scenario}: {role} process missing')
                    found,errors=load_report(folder/(role+'-report.json'),role);rows+=found;issues+=errors
    except Exception as e:
        issues.append(f'{type(e).__name__}: {e}')
    ids=[r['id'] for r in rows]
    if set(ids)!=expected:issues.append(f'Case manifest mismatch: missing={sorted(expected-set(ids))}, unexpected={sorted(set(ids)-expected)}')
    if len(ids)!=len(set(ids)):issues.append('Duplicate case IDs')
    passed=sum(r['passed'] for r in rows);failed=len(rows)-passed
    result={'suite':args.suite,'success':failed==0 and not issues,'cases':len(rows),'passed':passed,'failed':failed,'infrastructure_errors':issues,'mutation':args.inject_failure,'patched':not args.unpatched,'results':rows}
    (out/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    junit(rows,issues,out/'junit.xml')
    md=f'# OpenFire QA execution\n\nSuccess: {result["success"]}\n\nCases: {len(rows)}, passed: {passed}, failed: {failed}.\n\nControlled mutation: {args.inject_failure}.\n\n'
    md+='\n'.join('- '+x for x in issues)+'\n\n| Case | Result |\n|---|---|\n'+'\n'.join(f'| {r["id"]} | {"PASS" if r["passed"] else "FAIL"} |' for r in rows)+'\n'
    (out/'summary.md').write_text(md)
    print(json.dumps({k:v for k,v in result.items() if k!='results'},ensure_ascii=False,indent=2))
    return 0 if result['success'] else 1
if __name__=='__main__':raise SystemExit(main())
