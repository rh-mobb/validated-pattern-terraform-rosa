# Design: `rosactl` — human-friendly cluster CLI

**Date:** 2026-07-29  
**Status:** Implemented (first pass on `feature/rosactl`)  


## Problem

`make cluster.<name>` (default: apply then bootstrap) works, but the terminal experience is a long undifferentiated stream of Terraform and script output. It is hard to see which major phase is running, how far along the pipeline is, or where to look when something fails. A full interactive TUI is unnecessary; operators mainly want clear step progress and a short live log window, with the full log available on disk when debugging.


## Goals

- Provide a **stdlib-only Python** CLI (`rosactl`) as the primary UX for cluster lifecycle operations.
- Show **current step `N/M`**, elapsed time, and roughly the **last 8 log lines** during long steps.
- Always **tee full output** to a log file under `clusters/<name>/logs/`.
- On failure, print the log path and a `less …` hint (no interactive pager prompt).
- Support **`--robot` / non-TTY / CI** mode that streams full output like today’s Make behavior.
- **Orchestrate existing** `scripts/cluster/*` (and related) workers — do not rewrite Terraform or bash business logic in v1.
- Eventually **replace Make for cluster ops**; keep Make for non-cluster development tasks (`fmt`, `lint`, `test`, docs).


## Non-goals

- Full-screen TUI, keybindings, or interactive log pager prompts.
- Extra Python dependencies (`requirements.txt` / PyPI packages).
- Multi-module Python package layout in v1 (single file only).
- Rewriting bash scripts or Terraform modules.
- Fancy status UI for every passthrough command in v1 (vpn, tunnel, validate, spoke, …).
- Removing non-cluster Make targets.


## Approaches considered

| Approach | Pros | Cons |
|----------|------|------|
| A. Pretty-print wrapper around `make -f Makefile.cluster …` | Minimal code; Make stays source of truth | Coarse steps; hard to show Init/Plan/Apply/bootstrap-admin separately; Make echo noise |
| **B. Orchestrate scripts directly from `rosactl`** | Matches step UX; scripts stay workers; clear human/robot modes | Step order lives in Python (must track today’s Make semantics) |
| C. Extract shared step runner used by both Make and `rosactl` first | Single source of truth for order | Larger first PR; premature before CLI proves useful |

**Selected: B.**


## Design

### Architecture

```
rosactl (UX + step orchestration, stdlib Python)
    └── scripts/cluster/*.sh (+ info/vpn/tunnel scripts as needed)
            └── terraform / oc / helm / aws …
```

| Mode | When | Terminal behavior |
|------|------|-------------------|
| Human | TTY and not `--robot` | Step header + last ~8 log lines; completed steps as one ✓ line |
| Robot | `--robot`, non-TTY, or `CI=true` | Full stream (Make-like); still tee to log file |

`--verbose` on a TTY streams full output live while still showing step headers (and still tees).


### Packaging

Single executable file:

```
bin/rosactl    # #!/usr/bin/env python3 — argparse, runner, steps, passthroughs
```

No `requirements.txt`. Requires `python3` on `PATH` (already assumed for `scripts/verify_cluster.py`).


### CLI surface

Shape: `rosactl cluster <verb> <cluster-name> [flags]`

**v1 verbs with status+log UX (happy path):**

| Verb | Behavior |
|------|----------|
| `up` | apply + bootstrap (today’s default `make cluster.<name>`) |
| `plan` | init + plan |
| `apply` | init + plan + apply |
| `bootstrap` | bootstrap admin create → ensure tunnel → GitOps → tear down admin |
| `destroy` | destroy infrastructure (status+log around existing script) |
| `sleep` | sleep / cleanup with preserved resources (status+log) |
| `login` | thin passthrough to existing login script |
| `show-credentials` / `show-endpoints` | thin passthrough to existing info scripts |

**Flags (v1):**

| Flag | Purpose |
|------|---------|
| `--robot` | Force robot/full-stream mode |
| `--verbose` | Live full stream on TTY |
| `--no-bootstrap` | On `up`, stop after apply |

**Other cluster ops** (`vpn-*`, `tunnel-*`, `validate*`, `bootstrap-spoke`, `teardown-spoke`, `verify`, …): thin passthroughs in v1 — invoke the same underlying scripts, tee logs, no `N/M` step UI yet.


### Happy-path step model (`up`)

Example numbering (exact labels can be tuned in implementation):

1. Terraform Init  
2. Terraform Plan  
3. Terraform Apply  
4. Bootstrap admin create  
5. Ensure tunnel (no-op when Client VPN not deployed)  
6. Bootstrap GitOps  
7. Tear down bootstrap admin  
8. Done (short credentials/endpoints summary when available)

`plan` / `apply` / `bootstrap` use the relevant subset of these steps with renumbered `N/M`.


### Human UX

During an active step:

```
✓ Terraform Plan          2/8 · 18s
◐ Terraform Apply         3/8 · 12m 04s
  … up to 8 most recent log lines …
```

- Active step shows a **rolling viewport of the last ~8 log lines** (small ANSI redraw of that block only — not a full-screen TUI).
- Header line updates in place for spinner / elapsed time when the terminal supports it.
- Completed steps collapse to a single ✓ line (per-step log viewport is cleared from the screen; full output remains in the tee’d file).
- If redraw is unreliable (`TERM=dumb`, pipes, etc.), fall back to append-only streaming under the header.

**Logging:**

- Path: `clusters/<name>/logs/<timestamp>-<verb>.log`
- Convenience: `clusters/<name>/logs/latest.log` (symlink or copy of the current/last run)
- Tee combined stdout + stderr for every run

**On failure:**

- Mark failed step with ✗
- Keep last ~8 lines visible (including error)
- Print:

  ```
  Full log: clusters/<name>/logs/<timestamp>-<verb>.log
    less clusters/<name>/logs/<timestamp>-<verb>.log
  ```

- Exit non-zero
- No “open in less?” prompt


### Bootstrap admin lifecycle

Mirror today’s Make `bootstrap` semantics:

- Create short-lived bootstrap HTPasswd admin before GitOps bootstrap
- **Always** tear down on exit (success or failure) — `rosactl` owns cleanup equivalent to the Make `EXIT` trap
- Do not leave bootstrap IDP enabled after the command finishes


### Make migration

| Phase | Action |
|-------|--------|
| 1 | Ship `bin/rosactl`; document as preferred for cluster ops |
| 2 | `make cluster.%` prints a deprecation warning and delegates to `rosactl --robot cluster …` |
| 3 | Update getting-started / operations docs to `rosactl cluster up <name>` |
| 4 | Remove cluster Make targets when callers have moved |

**Keep** root Make (and related) for: `fmt`, `lint`, `test`, `validate` (code quality), docs preview/build, and other non-cluster developer workflows.


### Error handling

- Missing cluster directory → clear error listing available `clusters/*`
- Missing `python3` → clear error (same expectation as verify)
- Worker script non-zero exit → fail the current step, run any registered cleanup (e.g. bootstrap admin destroy), print log path, exit non-zero
- `NO_COLOR` / non-TTY → disable ANSI colors


### Testing

- Stdlib `unittest` for: robot-mode detection, log path naming, step list composition for `up`/`plan`/`apply`/`bootstrap`
- Manual smoke: `rosactl cluster plan <existing-cluster>` in human and `--robot` modes
- CI does not require a live ROSA cluster create for v1


## Out of scope / follow-ups

- Split into a Python package if the single file becomes hard to maintain
- Richer per-command step UI for vpn/validate/spoke
- Shared step definition consumed by both Make and `rosactl` (Approach C) if duplication becomes painful
- Add `.superpowers/` to `.gitignore` (brainstorm mockups; unrelated to runtime)


## References

- Current default flow: root `Makefile` `cluster.%` → `Makefile.cluster` `apply` then `bootstrap`
- Workers: `scripts/cluster/init-infrastructure.sh`, `plan-infrastructure.sh`, `apply-infrastructure.sh`, `bootstrap-admin.sh`, GitOps bootstrap script from Terraform outputs
- Related: `docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md`
