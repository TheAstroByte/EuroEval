"""Compute the worker's utilisation u = 0.8 x usable / cap from a fresh snapshot."""
import json, re, subprocess, mlx.core as mx
vm = subprocess.check_output(["vm_stat"], text=True)
page = int(re.search(r"page size of (\d+) bytes", vm)[1])
avail = sum(int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1]) for k in ("free", "inactive")) * page
cap = int(mx.device_info()["max_recommended_working_set_size"])
usable = min(cap, max(0, avail - 2**30))
print(json.dumps({"available": avail, "cap": cap, "usable": usable, "u": round(0.8 * usable / cap, 4)}))
