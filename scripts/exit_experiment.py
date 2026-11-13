"""Controlled fault injection; never classify the injected failure as a product bug."""
from pathlib import Path
from capture import capture
from prepare import prepare, ROOT
G=str(ROOT/'.runtime/Godot.app/Contents/MacOS/Godot')
out=ROOT/'evidence/exit-code'
for patched in [False,True]:
    game=prepare(patched)
    path=game/'tests/smoke.gd';s=path.read_text()
    if patched: s=s.replace('var qa_ok: bool = ', 'var qa_ok: bool = false and ',1)
    else: s=s.replace('print("SMOKE: DONE ok=", ', 'print("SMOKE: DONE ok=", false and ',1)
    path.write_text(s)
    capture([G,'--headless','--path',str(game),'res://tests/smoke.tscn'],out/('smoke-injected-fixed' if patched else 'smoke-injected-original'),90)
# Also prove the host's real missing-client failure now has a failing exit code.
game=prepare(True)
capture([G,'--headless','--path',str(game),'res://tests/net_host.tscn'],out/'net-no-client-fixed',25)
