# EuroEval issue 2310 coordination

Start with [the shared status](communication/2310/STATUS.md).

This branch holds briefs, Mac results, and implementation notes for the two machines working on [issue 2310](https://github.com/EuroEval/EuroEval/issues/2310). It has its own history and contains no evaluation source or CI workflows.

Implementation belongs on `feat/2310-apple-gpu-worker`. Keep coordination commits on `coord/2310` and use a separate checkout for each branch. The pull request remains based on the implementation branch.

## Read from an existing implementation checkout

Use the remote that points to `TheAstroByte/EuroEval`. If that remote is named `fork`:

```bash
git fetch fork coord/2310
git show FETCH_HEAD:communication/2310/STATUS.md
```

This reads the status without switching the implementation checkout's branch.

## Write from a separate coordination checkout

One-time setup on the other machine:

```bash
git clone --single-branch --branch coord/2310 https://github.com/TheAstroByte/EuroEval.git ~/Developer/EuroEval-2310-coord
cd ~/Developer/EuroEval-2310-coord
```

For later updates, start with `git pull --ff-only`. Add a dated brief, result, or implementation note, and update `communication/2310/STATUS.md` with the tested commit, outcome, and next action. Follow the machine's normal commit attribution and review instructions, then push only `coord/2310`:

```bash
git push origin HEAD:coord/2310
```

If another machine has pushed first, reconcile its changes and preserve both machines' notes before retrying. Keep published run evidence immutable. A later run gets a new directory named for its tested commit.

## Where files go

- `communication/2310/briefs/` holds dated run instructions and explicit updates.
- `communication/2310/mac-results/` holds findings, selected logs, and verified evidence bundles.
- `communication/2310/implementation-notes/` holds the implementation machine's commit summaries and requests for testing.
- `communication/2310/STATUS.md` is the current handoff between machines.

Write an implementation note with its branch commit, changed behaviour, local verification, and the exact Mac test requested. The Mac records the tested SHA and gate result in its own result directory. Missing gate evidence stays unproven.

The fork is public. Publish reviewed briefs and sanitised results here; keep credentials, `.env`, worker state, and model weights on their own machines. The supplied archives were checked for those state files and token patterns. Selected log copies have terminal formatting removed; the archives preserve the originals. Their original local publication notes are historical; use `STATUS.md` for current issue-comment publication status.

Posting an issue comment still follows the run brief's text-approval step. Adding a file here does not start a test or authorise live worker activity. Keep the operator's existing execution instructions in effect.

The evidence archives retain tested upstream source extracts. vllm-metal source retains its upstream notices and is covered by the included [Apache 2.0 license](communication/2310/licenses/vllm-metal-APACHE-2.0.txt). The project license is [MIT](LICENSE).
