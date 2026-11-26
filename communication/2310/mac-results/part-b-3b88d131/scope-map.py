"""Map finalised record datasets to task groups in api/worker/scope-policy.json."""
import json, sys
from pathlib import Path

repo = Path('/Users/daniel/Developer/EuroEval-2310-3b88d131')
policy = json.loads((repo / 'api/worker/scope-policy.json').read_text())
# records input: a results jsonl from the state dir results/ or a probe records list
records_file, language, model_type = sys.argv[1], sys.argv[2], sys.argv[3]
pol = next(p for p in policy['policies'] if p['language'] == language and p['model_type'] == model_type)
groups = pol['task_groups']
# dataset -> task group mapping comes from euroeval's dataset registry if available
try:
    sys.path.insert(0, str(repo / 'src'))
    from euroeval.dataset_registry import DATASETS  # type: ignore
except Exception:
    DATASETS = None
mapping = {}
if DATASETS:
    for name, ds in DATASETS.items():
        task = getattr(ds, 'task', None)
        mapping[name] = str(task)
seen = {}
for line in Path(records_file).read_text().splitlines():
    if not line.strip():
        continue
    r = json.loads(line)
    ds = r.get('dataset') or r.get('dataset_name') or ''
    seen.setdefault(ds, 0)
    seen[ds] += 1
out = {'language': language, 'model_type': model_type, 'task_groups_in_scope': groups,
       'datasets_seen': seen, 'dataset_task_map': {k: mapping.get(k) for k in seen}}
print(json.dumps(out, indent=2))
