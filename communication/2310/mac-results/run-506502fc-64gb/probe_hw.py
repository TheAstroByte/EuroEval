"""Time the worker's hardware discovery and check it against independent readings."""
import json, re, subprocess, sys, time
from euroeval_worker.hardware import NoGpuError, discover_hardware

def available():
    vm = subprocess.check_output(["vm_stat"], text=True)
    page = int(re.search(r"page size of (\d+) bytes", vm)[1])
    return sum(int(re.search(rf"Pages {k}:\s+(\d+)", vm)[1]) for k in ("free", "inactive")) * page

cap = int(subprocess.check_output([sys.executable, "-c",
    "import mlx.core as mx; print(mx.device_info()['max_recommended_working_set_size'])"], text=True))
memsize = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))
seconds, report, avail = [], None, None
try:
    for _ in range(3):
        avail = available()
        start = time.monotonic()
        report = discover_hardware()
        seconds.append(round(time.monotonic() - start, 2))
except NoGpuError as error:
    print(json.dumps({"pass": False, "error": f"NoGpuError: {error}", "seconds": seconds}))
    sys.exit(1)
gpu = report.gpus[0]
expected_free = min(cap, max(0, avail - 2**30))
checks = {
    "one_gpu_metal_0": len(report.gpus) == 1 and gpu.uuid == "metal-0",
    "total_equals_mlx_cap": gpu.total_memory_bytes == cap,
    "free_within_2pct": abs(gpu.free_memory_bytes - expected_free) <= 0.02 * cap,
    "ram_equals_hw_memsize": report.ram_bytes == memsize,
}
print(json.dumps({"pass": all(checks.values()), "checks": checks, "seconds": seconds,
                  "gpu": {"name": gpu.name, "uuid": gpu.uuid, "total": gpu.total_memory_bytes,
                          "free": gpu.free_memory_bytes},
                  "mlx_cap": cap, "available": avail, "expected_free": expected_free,
                  "ram_bytes": report.ram_bytes, "hw_memsize": memsize,
                  "pytorch_version": report.pytorch_version}, indent=2))
sys.exit(0 if all(checks.values()) else 1)
