#!/usr/bin/env python3
"""Capture a real subprocess and its exit/timeout, with no shell pipelines."""
import argparse, datetime, json, os, platform, signal, subprocess, time
from pathlib import Path


def capture(command, output, timeout=120, cwd=None, env=None):
    output = Path(output); output.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    begin = time.monotonic(); timed_out = False
    with output.with_suffix('.log').open('w') as log:
        p = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(p.pid, signal.SIGTERM)
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL); p.wait()
    result = {'command': command, 'cwd': str(Path(cwd or '.').resolve()),
              'started_utc': started, 'duration_seconds': round(time.monotonic()-begin, 3),
              'exit_code': p.returncode, 'timed_out': timed_out, 'timeout_seconds': timeout,
              'platform': platform.platform()}
    output.with_suffix('.json').write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result

if __name__ == '__main__':
    a = argparse.ArgumentParser(); a.add_argument('--out', required=True); a.add_argument('--timeout', type=float, default=120)
    a.add_argument('command', nargs=argparse.REMAINDER); args=a.parse_args()
    cmd=args.command[1:] if args.command[:1]==['--'] else args.command
    r=capture(cmd,args.out,args.timeout)
    raise SystemExit(124 if r['timed_out'] else r['exit_code'])
