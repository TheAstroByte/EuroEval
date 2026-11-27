"""Report whether hardware discovery refuses under the current environment."""
import json
from euroeval_worker.hardware import NoGpuError, discover_hardware
try:
    discover_hardware()
    print(json.dumps({"refused": False}))
except NoGpuError as error:
    print(json.dumps({"refused": True, "message": str(error)}))
