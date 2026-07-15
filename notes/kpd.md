# KPD (Kernel Patches Daemon)

Quick reference for KPD.

## What It Does

Bridges Patchwork (patchwork.kernel.org) with GitHub repos (kernel-patches/bpf, kernel-patches/bpf-next). Watches for new BPF patch series on the mailing list, creates/updates GitHub PRs, runs CI via GitHub Actions, posts results back to Patchwork, and sends email notifications.

## Data Flow

```
Mailing list (LKML/BPF)
    -> Patchwork (indexes patch series)
    -> KPD (polls every ~2 min)
        -> Mirrors upstream tree (git.kernel.org) to GitHub
        -> Downloads mbox from Patchwork
        -> git am --3way on top of upstream + CI files
        -> Force-pushes branch: series/<id>=><target>
        -> Creates/updates GitHub PR
    -> GitHub Actions runs CI (vmtest workflows)
    -> KPD reads workflow results
        -> Posts checks back to Patchwork
        -> Sends email notification to patch author
        -> Forwards allowlisted PR comments to mailing list
```

## Source Code

**Canonical source**: https://github.com/kernel-patches/kernel-patches-daemon

### Key Modules (under `kernel_patches_daemon/`)

| Module | Purpose |
|--------|---------|
| `daemon.py` | Main loop: `KernelPatchesWorker` runs `sync_patches()` every 120s |
| `github_sync.py` | Orchestrator: creates `BranchWorker` per branch, coordinates full sync cycle |
| `branch_worker.py` | Heavy lifter: git operations, PR create/update, CI sync, email, branch cleanup |
| `patchwork.py` | Patchwork REST API client: `Subject`, `Series`, `Patch` abstractions |
| `github_connector.py` | GitHub auth (OAuth or GH App), token refresh monkey-patch |
| `github_logs.py` | Extracts test_progs failure logs from GH Actions for email notifications |
| `config.py` | Config v3 dataclasses: `KPDConfig`, `BranchConfig`, tag-to-branch mapping |
| `status.py` | Status enum + GH conclusion mapping |
| `stats.py` | Counters + OpenTelemetry histogram timers |

## Configuration

Target repos from `configs/kpd.json`:
- **Patchwork**: patchwork.kernel.org, project `bpf`, delegate ID 77147, 7-day lookback
- **bpf-next**: upstream from `git.kernel.org/bpf/bpf-next.git` -> `kernel-patches/bpf`
- **bpf**: upstream from `git.kernel.org/bpf/bpf.git` -> `kernel-patches/bpf`
- **CI repo**: `kernel-patches/vmtest` (workflows copied into PR branches)
- **Tag routing**: `bpf` -> bpf only, `bpf-next` -> bpf-next only, default -> try bpf-next first

## Notable Technical Details

- **Token refresh hack**: Monkey-patches PyGithub's refresh threshold from 20s to 30min so tokens in git URLs stay valid during operations
- **Email via curl**: Uses `curl` with SMTP-over-HTTP-proxy for proxied environments
- **Reference clone**: Uses a local reference clone of the upstream tree (configurable path) for faster git clones
- **Rate limiting**: Stops sync when GitHub API tokens < 1000 remaining
- **Merge conflicts**: Creates a PR with a dummy commit + `merge-conflict` label when `git am` fails

## Recent History

- **v1.0.0** released July 2025
- **Source of truth** moved to GitHub June 2025
- **PR comment forwarding**: Added for AI review comments -> mailing list relay
- **Dependency & CI-hygiene wave (Jun 23-24 2026)**: PR #46 (theihor, Jun 23) fixed an aiohttp-3.14 break, started tracking a dependency lockfile, expanded supported Python to **3.11-3.14**, and bumped black to 25; PR #47 (theihor, Jun 24) switched the container base image to `python:3-slim` and enabled per-PR Docker image builds (the "Docker Image Publish" workflow now runs on PR/feature branches, not just main); PR #45 (rppt = **Mike Rapoport, Microsoft** — KPD's first external adopter) added a `--no-metrics` CLI option to run KPD with the OpenTelemetry stats path disabled. Merging #45 surfaced the broken KPD GitHub CI, which #46/#47 then fixed.

## Key People

- **Ihor Solodrai** (theihor) — current maintainer
- **Daniel Mueller** — original developer
- **Manu Bretelle** — original developer
- **Nikolay Yurin** — original developer
- **Eduard Zingerman** — contributor

## Open Questions

- How does the PR comment -> email forwarding allowlist work in practice? Who's on it?
