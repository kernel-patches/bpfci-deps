# CI & Review Bots

The automated bots in the upstream BPF / kernel testing ecosystem: the AI review bots (Sashiko
and the BPF CI Bot) and the syzkaller fuzzer (syzbot). For the BPF CI Bot's own mechanics — the
per-commit review workflow and the weekly investigator — see ci-bot.md.

## Sashiko

A kernel-wide AI review bot:
- Operated by Google; open-source infrastructure at https://sashiko.dev.
- Multiple LLM backends, including frontier closed models.
- Emails reviews to patch authors (not reply-all to the list); reviews are also sent to
  `sashiko-reviews@lists.linux.dev`.
- Covers many subsystems (media, DT bindings, drm, ASoC, bpf, net, perf, …) and is expanding.

Review email format:
```
Thank you for your contribution! Sashiko AI review found N potential issue(s) to consider:
- [High] <brief description>
--
commit <sha>
Author: ...
<patch context and analysis>
--
Sashiko AI review · https://sashiko.dev/#/patchset/...
```

## The BPF CI Bot

BPF-specific AI review that runs inside BPF CI and posts findings as GitHub PR comments (KPD
forwards them to the mailing list). Full mechanics are in **ci-bot.md**.

How it differs from Sashiko:

| | Sashiko | BPF CI Bot |
|---|---|---|
| Delivery | Email to patch author | GitHub PR comment |
| Mailing list | Private + `sashiko-reviews` CC | via KPD comment forwarding |
| Tags | No formal tags | No tags |
| Scope | Kernel-wide (many subsystems) | BPF only |
| Trigger | Automatic on LKML patches | BPF CI (per-commit) |
| Model | Multiple (incl. frontier) | Claude Opus 4.8 + semcode MCP |

## syzbot

Google's continuous kernel fuzzer (syzkaller) — separate from the kernel-patches BPF CI, but part
of the same upstream testing ecosystem:

- Continuously fuzzes mainline and -next; on a crash it files a report and emails the relevant
  subsystem list, tracked at https://syzkaller.appspot.com. BPF (verifier, maps, program types)
  is one of the fuzzed surfaces.
- Fixes reference the report with `Reported-by: syzbot+<hash>@syzkaller.appspotmail.com` and
  `Closes: <url>`; `Tested-by: syzbot@…` is an accepted tag. A reproducer (C or syzlang) is
  usually attached and is the expected basis for a fix.
- Unlike Sashiko / the BPF CI Bot (static review), syzbot is dynamic — it reports runtime crashes.

## Community norms

AI-assisted review is broadly tolerated upstream. Tensions worth knowing when tuning a bot:

- **Tagging.** The community leans toward a dedicated `Scanned-by:`-style tag for AI involvement
  rather than borrowing `Reviewed-by:`, which stays human-only.
- **Noise.** False positives are the main complaint; emit few, high-confidence, reachable findings.
- **Human accountability.** Both AI *findings* and AI-authored *patches/replies* are held to a
  "a human must understand, test, and stand behind it" bar.
- **Realism over severity.** Maintainer direction favors reachability/realism over a bot's own
  severity label; an AI-flagged "bug" without a reproducer is generally treated as noise, not a fix.
