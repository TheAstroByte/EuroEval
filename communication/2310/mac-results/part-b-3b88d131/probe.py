import json, sys, time
from pathlib import Path
d = Path(sys.argv[1]); out = {"t": time.time()}
s = d / "state.json"
out["credential_present"] = s.exists() and bool(json.loads(s.read_text()).get("credential"))
a = d / "active-lease.json"
if a.exists():
    v = json.loads(a.read_text())
    out["lease_id"] = v["lease"]["lease_id"]; out["model"] = v["lease"]["model_id"]
    out["records"] = [{"digest": r["digest"], "acknowledged": r["acknowledged"]} for r in v.get("records", [])]
    out["finalised_submission_id"] = v.get("finalised_submission_id")
l = d / "last-submission.json"
out["last_submission_id"] = json.loads(l.read_text())["submission_id"] if l.exists() else None
print(json.dumps(out))
