from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from capture import capture
ROOT=Path(__file__).resolve().parents[1]
G=str(ROOT/'.runtime/Godot.app/Contents/MacOS/Godot');base=[G,'--headless','--path',str(ROOT/'.runtime/game')]
out=ROOT/'evidence/phase1'
with ThreadPoolExecutor(2) as pool:
    fs=[pool.submit(capture,base+['res://tests/'+role+'.tscn'],out/(role+'-baseline'),45) for role in ['net_host','net_client']]
    for f in fs: f.result()
capture(base+['res://tests/net_host.tscn'],out/'net-host-no-client-baseline',25)
