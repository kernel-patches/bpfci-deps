# BPF CI Bot & AI Code Review

The AI layer in BPF CI. Two autonomous workflows in `kernel-patches/vmtest`.

## AI Code Review (`ai-code-review.yml`)

Per-commit regression analysis on every PR in `kernel-patches/bpf`.

**Pipeline:**
1. `get-commits` job lists PR commits (max 50)
2. Matrix fans out: one `ai-review` job per commit
3. Each job: checkout Linux at commit → `semcode-index --git` (diff range) + `--lore bpf` → checkout `masoncl/review-prompts`
4. `claude-code-action` with `--max-turns 100`, model `claude-opus-4-8` via AWS Bedrock (OIDC auth)
5. Prompt: "Read `review/review-core.md`, deep dive regression analysis of HEAD commit"
6. If finding → writes `review-inline.txt` → `post-pr-comment.js` posts to PR → KPD emails to mailing list → job exits 42 (CI failure signal)
7. No finding → no comment, job passes

**Key design decisions:**
- Per-commit (not per-PR) to isolate findings per patch
- semcode MCP provides `find_function`, `find_callers`, `find_callees`, `find_callchain`, `grep_functions`, `diff_functions`, lore search
- GitHub App token (`KP_REVIEW_BOT_APP_ID`) for PR interaction
- `allowed_bots: kernel-patches-daemon-bpf,kernel-patches-review-bot`
- Runner: `ai-review` Docker image (Debian, has semcode pre-indexed, gcc-14, llvm-19, lei)

**History:** Started Sep 2025 (Sonnet 3.5), switched to Opus 4.5 (Dec 2025), Opus 4.6 (Feb 2026), Opus 4.8 (May 2026, vmtest PR #487). semcode integration added Feb 5. Review metadata tags added Jan 26 then removed Mar 2. First public AI code review on Linux kernel mailing list.

## BPF CI Bot (`ai-agent.yml`)

Weekly autonomous agent investigating recurring CI failures.

**Schedule:** Monday 4am PT (cron `0 12 * * 1` UTC) + manual dispatch + PR trigger on prompt/workflow changes.

**Environment setup:**
1. Checkout 8 companion repos into `github/` directory (vmtest, runner, KPD, libbpf/ci, danobi/vmtest, semcode, review-prompts, nojb/public-inbox)
2. Install tools: gcc-14, llvm-19, python3, jq, lei, gh CLI
3. `get-linux-source` with `FETCH_DEPTH: 0` (full clone of bpf-next)
4. Move Linux source to workspace root (replaces `.git`)
5. `semcode-index --git` (torvalds merge-base..HEAD) + `--lore bpf`
6. Restore `NOTES.md` from GitHub Actions cache

**Agent execution:**
- `claude-code-action` with `--max-turns 200`, model `claude-opus-4-8`
- Prompt: "Read agent.md and follow the directions"
- Has access to: Bash, Edit, Write, WebFetch, semcode MCP, GitHub CI MCP
- Denied: general GitHub MCP

**4-phase protocol** (`bpf-ci-agent.md`):
1. **Phase 0 — Load Context:** Read NOTES.md, list open/closed vmtest issues, build skip list of already-investigated issues
2. **Phase 1 — Gather Candidates:** Examine 5–8 failed CI runs across independent PRs (`gh run list/view`), search lore for CI discussions, check denylists and recent CI commits. Build scored candidate table (frequency, severity, novelty)
3. **Phase 2 — Select Issue:** Score by novelty (highest), frequency, impact, feasibility. Pick one
4. **Phase 3 — Investigate:** Reproduce locally via vmtest (build kernel + selftests + QEMU boot), root-cause analysis (code reading, git history, lore, semcode), develop fix if warranted
5. **Phase 4 — Output:** Write `output/summary.md` + `.patch` files. Post-output job creates GitHub issue with `[bpf-ci-bot]` prefix, patches as comments

**Rules / Anti-patterns:**
- Never investigate patch-specific failures (submitter's job)
- Only investigate cross-PR recurring issues
- Check skip list before every investigation
- Never `cd` (working directory persistence)
- Max 3 semcode retries → fall back to lei → git log --grep
- Batch up to 4 parallel `gh` calls

**Output format:** GitHub issue with Summary, Failure Details, Root Cause Analysis, Proposed Fix, Impact, References. Patches tagged `Generated-by: BPF CI Bot ($LLM_MODEL_NAME) <bot+bpf-ci@kernel.org>`.

**NOTES.md:** Persistent state across runs (GitHub Actions cache). Tracks known issues, skip list, investigation history. Updated every run.

## Infrastructure

| Component | Location |
|-----------|----------|
| Agent prompt | `ci/claude/bpf-ci-agent.md` |
| Agent workflow | `.github/workflows/ai-agent.yml` |
| Review workflow | `.github/workflows/ai-code-review.yml` |
| Claude settings | `ci/claude/settings.json` |
| MCP config | `ci/claude/mcp.json` |
| PR comment script | `ci/claude/post-pr-comment.js` |
| README | `ci/claude/README.md` |
| Review prompts | `masoncl/review-prompts` (external repo) |
| AI runner image | `kernel-patches/runner:ai-review` |

## Key People

- **Ihor Solodrai** — infra plumber, built the bot, maintains workflows
- **Chris Mason** — prompt engineer, maintains `review-prompts`
