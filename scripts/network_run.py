"""Spawn two independent Godot processes, wait for socket readiness, collect both."""
import concurrent.futures, json, socket, time
from pathlib import Path
from capture import capture

def run_network(godot, game, out, scenario='combat', verbose=False):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    # Choose a free local UDP port; a bind race is still possible, surfaced as failure.
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
        s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    def cmd(role):
        return [str(godot), *(['--verbose'] if verbose else []),'--headless','--path',str(game),'res://tests/qa/network.tscn','--',f'--role={role}',f'--scenario={scenario}',f'--port={port}',f'--report={out/(role+"-report.json")}']
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        host=pool.submit(capture,cmd('host'),out/'host-process',45)
        ready=False
        for _ in range(150):
            p=out/'host-process.log'
            if p.exists() and 'QA_HOST_READY' in p.read_text(errors='replace'):ready=True;break
            if host.done():break
            time.sleep(.05)
        if not ready:
            return [host.result()]
        client=pool.submit(capture,cmd('client'),out/'client-process',40)
        return [host.result(),client.result()]
