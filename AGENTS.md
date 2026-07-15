# bpfci-deps — BPF CI bootstrap

A single clone-and-go starting point for **upstream BPF CI** development. It gathers the source
repositories of the CI pipeline as git submodules (`deps/`) and ships curated reference notes
(`notes/`) so you can start working — by hand or with an agent — without hunting down where
everything lives.

Upstream BPF CI is spread across ~7 repos. This repo puts them in one tree with a map.

## Quick start

```bash
git clone --recurse-submodules https://github.com/kernel-patches/bpfci-deps
```

Start your agent in this directory: `AGENTS.md` (this file) and `CLAUDE.md` (a symlink to it)
auto-load, giving it the dependency map below and the reference notes in `notes/`.

## The dependencies (`deps/`)

Each is an independent public git repo, pinned as a submodule. Bump all with
`git submodule update --remote`.

| Path | Role |
|---|---|
| `deps/kernel-patches/vmtest` | **Top-level CI.** GitHub Actions workflow defs (`test.yml` = `bpf-ci`), `matrix.py` (build matrix + runner labels), `stagger.py`, and the AI-review prompts/config under `ci/claude/`. Start here to change *what* CI runs. |
| `deps/libbpf/ci` | **On-runner actions.** The composite actions the workflows call — `build-linux`, `build-selftests`, `run-vmtest`, `setup-build-env`, veristat — plus the ansible that provisions the self-hosted runner fleet. Start here to change *how* a build/test step runs. |
| `deps/kernel-patches/runner` | **Runner images.** Dockerfiles for the runner variants (main test runner, `kbuilder-debian` build image, `ai-review`, `s390x`) + nightly publish workflows. |
| `deps/danobi/vmtest` | **The VM runner.** The `vmtest` binary (Rust) that boots the built kernel under QEMU/KVM to run selftests. `run-vmtest` (in `libbpf/ci`) fetches and drives it. |
| `deps/kernel-patches/kernel-patches-daemon` | **KPD.** Polls patchwork, applies each series onto the base + CI files, pushes branches/PRs to `kernel-patches/bpf`, and reports results back to patchwork/lore. Feeds the pipeline. |
| `deps/facebookexperimental/semcode` | **Semantic code search** for C/C++/Rust kernel trees, with an MCP server used by the AI review. Build and wire it per its own README (setting it up is out of scope for this repo). |
| `deps/masoncl/review-prompts` | **AI review prompts.** The kernel review/debug/verify prompt packs (`/kreview`, `/kdebug`, `/kverify`) the CI AI reviewer uses. Install into your agent with its own `setup.sh <agent> kernel`. |

## How the pipeline fits together

```
mailing list (bpf / netdev) → patchwork (netdevbpf)
      │  KPD polls, git-am's each series + CI files, pushes series/<id> + PR
      ▼  → kernel-patches/bpf
GitHub Actions: test.yml  (name: bpf-ci)                 [deps/kernel-patches/vmtest]
      │  matrix.py → per (arch × toolchain) fan-out
      ├─ build ──────► AWS CodeBuild (kbuilder image) → vmlinux + selftests artifact
      ├─ test ───────► self-hosted bare-metal (KVM)   [deps/libbpf/ci run-vmtest → danobi/vmtest]
      ├─ veristat ───► verifier-perf regression check (kernel / meta / scx / cilium corpora)
      └─ ai-review ──► per-commit Claude review (Bedrock)  [ci/claude + semcode + review-prompts]
      ▼  results → patchwork checks / author email / forwarded to lore     [KPD]
```

Full detail is in `notes/` — start at **`notes/SUMMARY.md`**.

## Working locally

- **Change what CI does:** edit the workflows + `matrix.py` in `deps/kernel-patches/vmtest`;
  the actual build/test steps live as composite actions in `deps/libbpf/ci`.
- **Reproduce a build/test:** the `deps/libbpf/ci` actions are ordinary scripts
  (`build-linux/`, `build-selftests/`, `run-vmtest/`) you can run against a kernel checkout.
  `run-vmtest` fetches `danobi/vmtest` and boots QEMU under KVM.
- **Runner / image questions:** the Dockerfiles in `deps/kernel-patches/runner`.
- **Navigate kernel code:** `deps/facebookexperimental/semcode` provides semantic code search
  and an MCP server for AI tools (`func`, `callers`, `callchain`, type/struct lookup); build and
  run it against a kernel checkout per its own README.
- **AI code review flow:** `deps/masoncl/review-prompts` provides `/kreview`, `/kdebug`,
  `/kverify`; run its `setup.sh <agent> kernel` to install them for your agent.

## Reference notes (`notes/`)

Curated reference docs — read on demand. Index: **`notes/SUMMARY.md`**. Covers the
CI pipeline, the AI review bot, veristat, selftests (incl. authoring conventions), test
infrastructure, GCC-BPF CI, KPD, and the CI/review bots (incl. syzbot).

## Conventions

- `deps/` are upstream repos — don't edit them here; send changes upstream.
- Keep `notes/` entries focused and indexed in `notes/SUMMARY.md`.
