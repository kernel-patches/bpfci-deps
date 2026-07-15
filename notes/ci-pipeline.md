# BPF CI — Upstream Pipeline

Quick reference for the upstream BPF CI system.

## Upstream CI (Public GitHub Actions)

### Data Flow

```
Mailing list (lore.kernel.org)
    → Patchwork (indexes patches)
    → KPD (creates GitHub PRs) — see kpd.md
    → GitHub repos (kernel-patches/bpf, kernel-patches/bpf-next)
    → GitHub Actions (vmtest workflows)
    → Self-hosted runners on AWS (CodeBuild)
    → Results → PRs, failure emails to authors
    → AI code review → mailing list
    → BPF CI Bot → GitHub Issues
```

### Key Repos (this repo's `deps/`)

| Repo | Purpose | Key files |
|------|---------|-----------|
| kernel-patches/vmtest | Workflow definitions + AI prompts | `.github/workflows/*.yml`, `ci/claude/bpf-ci-agent.md` |
| kernel-patches/runner | Runner Docker images | `Dockerfile`, `ai-review.Dockerfile`, `s390x.Dockerfile`, `kbuilder-debian.Dockerfile` |
| libbpf/ci | CI build/test scripts | `build-linux/`, `build-selftests/`, `run-vmtest/` |
| facebookexperimental/semcode | Semantic code search tool | `src/`, MCP server for AI code tools |
| masoncl/review-prompts | AI review prompts | Linux kernel-specific review prompts |

### Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ai-agent.yml` | Weekly Mon 4am PT + manual | BPF CI Bot — investigates failures, files issues |
| `ai-code-review.yml` | PR opened/review_requested | AI review of individual commits |
| `kernel-build-test.yml` | (reusable) | Combined build+test orchestrator |
| `kernel-build.yml` | (reusable) | Kernel + selftest build |
| `kernel-test.yml` | (reusable) | Test execution in VMs |
| `gcc-bpf.yml` | PR | GCC BPF backend builds |
| `veristat-*.yml` | PR | Veristat (kernel, cilium, meta, scx) |
| `lint.yml` | PR | Linting |

### Runner Images (kernel-patches/runner)

| Image | Base | Purpose |
|-------|------|---------|
| `runner:ubuntu-noble` | myoung34/github-runner | Main self-hosted runner (test execution) |
| `runner:kbuilder-debian-{arch}` | debian:testing | Kernel build (cross-compile for s390x/aarch64) |
| `runner:ai-review` | debian:latest | AI review: has semcode, git, mirror repos |
| `runner:s390x` | ubuntu:noble | Custom GHA runner for s390x |

`install-dependencies.sh` clones `libbpf/ci@v4`, caches GCC 15 + LLVM 21. AI image builds semcode from source and pre-indexes lore + bpf-next.

### CI Matrix (matrix.py)

4 configs: x86_64/GCC (veristat + parallel), x86_64/LLVM (release -O2), aarch64/GCC, s390x/GCC. Tests: `test_progs`, `test_progs_no_alu32`, `test_verifier`, `test_maps` (not s390x), `test_progs_cpuv4` (LLVM≥18), `sched_ext` (x86_64/aarch64). GCC BPF runner disabled. 30min timeout parallel, 360min otherwise.

Runners: auto-selects CodeBuild when >80% of self-hosted runners are busy.

### DEPLOYMENT Variable

Set in `kernel-test.yml`: `prod` for `kernel-patches/bpf`, `rc` otherwise. Maps to `DENYLIST.${DEPLOYMENT}` — so `DENYLIST.rc` has extra tests denied for release candidates (weaker stability guarantees).

### Architectures & Runners

x86_64 (primary), aarch64, s390x. Runners on AWS CodeBuild (migrated from bare-metal EC2). s390x on IBM LinuxOne. Ansible provisioning in `libbpf/ci/ansible/`.

### AI Stack

See ci-bot.md for full details on both AI workflows (AI Code Review + BPF CI Bot) and semcode tooling.

### Test Infrastructure & Allow/Denylist

See selftests.md for full details. Summary: vmtest wraps QEMU; test_progs uses `-a@`/`-d@` for allow/denylists; `prepare-bpf-selftests.sh` merges in-tree + CI-specific lists via `normalize_bpf_test_names.py`.

### BPF CI for Stable kernels (created 2026-06)

Lives in **`kernel-patches/linux-stable`** (in the kernel-patches org — its repos have the CI runner/hardware access and host the source-of-truth for most BPF CI code; NOT under `libbpf/`, NOT in `libbpf/libbpf`). Shung-Hsi Yu (SUSE) maintains the stable part. Repo layout: a `main` branch (CI code only), a Linux mainline mirror, and per-version `linux-X.Y.y` test branches.

A **daily sync job** (README-documented): syncs torvalds/master, then for each tracked stable version pulls the tree, applies stable-queue patches, and overlays `.github/` + `ci/` from `main` as one commit (KPD-like for bpf-next, but without patchwork/KPD), pushing to `linux-X.Y.y`. Push to `linux-*` triggers `test.yml` (currently a stub — build/test logic to be filled in, copyable from Shung-Hsi's libbpf fork).

Design guidance: `kbuilder-debian` was crafted for bpf-next and is not required (Shung-Hsi starts on Ubuntu 24.04; a `kbuilder-stable` could come later). Reuse a `libbpf/ci` action where possible; otherwise copy working yaml rather than keeping common parts compatible across stable and bpf-next — two diverged CI trees is expected and fine. A full `kernel-patches/bpf`-style pre-merge CI for incoming stable patchsets is explicitly NOT required now (possibly ever).
