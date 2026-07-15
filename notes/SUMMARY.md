# notes/ — curated upstream BPF CI reference

Reference notes for working on BPF CI. Read on demand; each note stands alone.

## The CI system
- **ci-pipeline.md** — the upstream pipeline end-to-end: mailing list → patchwork → KPD →
  GitHub Actions → runners → results back. Build matrix (`matrix.py`), workflows, runner
  images, DEPLOYMENT/denylists, architectures, and the stable-kernel CI offshoot.
- **ci-bot.md** — the AI layer in `kernel-patches/vmtest`: per-commit AI code review +
  the weekly BPF CI Bot, and how semcode fits in.
- **kpd.md** — the Kernel Patches Daemon: what it does, data flow, key modules, config,
  and recent history. Source lives in `deps/kernel-patches/kernel-patches-daemon`.

## Test infrastructure
- **selftests.md** — how BPF selftests are built, run, and configured in CI: `test_progs`
  framework, discovery, parallel execution, allow/deny lists, known-flaky handling; plus a
  condensed set of conventions for authoring selftests.
- **test-infra.md** — the three-layer test system: `test_progs`, `test_loader`
  (BTF-annotation verifier tests), and `BPF_PROG_TEST_RUN`.
- **gcc-bpf.md** — GCC-BPF backend CI: the build-only workflow, the denylist, and the
  `theihor/gcc-bpf` releases it consumes.
- **veristat.md** — the veristat verifier-perf regression tool and how CI uses it: the four
  corpora, push-baseline / PR-compare, and the success→failure fail condition.

## Bots
- **bots.md** — the ecosystem's automated bots: AI review (Sashiko, the BPF CI Bot) and the
  syzkaller fuzzer (syzbot), plus community norms for AI-assisted review.
