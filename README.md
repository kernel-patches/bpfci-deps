# bpfci-deps

A clone-and-go workspace for upstream **BPF CI** development: the source repositories of
the CI pipeline as git submodules, curated reference notes, and AI-agent tooling — in one
place. Upstream BPF CI is spread across ~7 repos; this gathers them with a map so you (or an
agent) can start working without hunting down where everything lives.

## Quick start

```bash
git clone --recurse-submodules https://github.com/kernel-patches/bpfci-deps
```

Then read **[AGENTS.md](AGENTS.md)** for the dependency map and how the pipeline fits
together, and **[notes/SUMMARY.md](notes/SUMMARY.md)** for the CI reference.

## Layout

- `deps/` — the BPF CI source repos as submodules: `kernel-patches/vmtest` (workflow defs),
  `libbpf/ci` (on-runner actions), `kernel-patches/runner` (runner images), `danobi/vmtest`
  (VM runner), `kernel-patches/kernel-patches-daemon` (KPD), `facebookexperimental/semcode`
  (code search + MCP), `masoncl/review-prompts` (AI review prompts).
- `notes/` — curated reference docs (see `notes/SUMMARY.md`).
- `AGENTS.md` / `CLAUDE.md` — agent entry point: the dependency map + how the pipeline fits together.

## Contributing

The `deps/` entries are independent upstream repos — send changes to them upstream, not here.
