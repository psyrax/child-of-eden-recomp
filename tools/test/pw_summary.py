# Summarizes `pw-dump` (JSON on stdin): one line per PipeWire Link and Node with its state and error. Used by pw_test_inner.sh.
import json,sys
for o in json.load(sys.stdin):
    t=o.get("type","").split(":")[-1]; i=o.get("info",{}) or {}
    if t=="Link": print("Link",o["id"],"state",i.get("state"),"err",i.get("error"),"fmt",json.dumps(i.get("format"))[:200],i.get("output-node-id"),"->",i.get("input-node-id"))
    if t=="Node": print("Node",o["id"],i.get("props",{}).get("node.name"),"state",i.get("state"),"err",i.get("error"),"driver",i.get("props",{}).get("node.driver"),"params",list((i.get("params") or {}).keys()))
