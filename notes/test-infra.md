# BPF Test Infrastructure

## Overview

Three-layer system: **test_progs** framework (userspace test harness), **test_loader** (BTF-annotation-driven verifier tests), and **BPF_PROG_TEST_RUN** (kernel-side program execution).

- `tools/testing/selftests/bpf/test_progs.c` — 2,124 lines, main test harness
- `tools/testing/selftests/bpf/test_loader.c` — 1,406 lines, annotation-based test runner
- `net/bpf/test_run.c` — 1,844 lines, kernel BPF_PROG_TEST_RUN implementations
- 420 test files in `prog_tests/`, 954 BPF program files in `progs/`

## test_progs Framework

### Test Registration
- Auto-discovered via naming convention: `void test_<name>(void)` or `void serial_test_<name>(void)`
- `prog_tests/tests.h` generated at build time from filenames in `prog_tests/`
- X-macro pattern: `DEFINE_TEST(name)` expands to both extern decl and struct init
- `prog_test_def` struct: `test_name`, `run_test` (parallel-safe), `run_serial_test` (exclusive)

### Parallel Execution (`-j` flag)
- Main process spawns N worker processes via `fork()`
- Unix domain socket pairs for IPC (MSG_DO_TEST / MSG_TEST_DONE / MSG_TEST_LOG / MSG_SUBTEST_DONE)
- Dispatch threads (one per worker) grab tests from shared index under `current_test_lock`
- `serial_test_*` functions skip parallel dispatch — run sequentially after workers finish
- Tests prefixed `ns_` auto-create isolated network namespaces

### Test Selection
- `-t name` substring match, `-a pattern` glob match, `-d pattern` glob deny
- `-b name` blacklist, `-n NUM` by number, `@file` list from file
- Whitelist/blacklist with glob_match supporting `*` wildcard
- Subtests selectable via `test_name/subtest_name` syntax

### stdio Hijack
- Each test's stdout/stderr captured via `open_memstream` into per-test/subtest log buffers
- Logs forwarded to main process via MSG_TEST_LOG chunks (8KB max per chunk)
- On failure, log buffers printed; on success, suppressed unless verbose

### Watchdog
- POSIX timer (`timer_create` with SIGEV_THREAD)
- Two-phase: notify after `secs_till_notify`, SIGSEGV kill after `secs_till_kill`
- Reset per test/subtest via watchdog_start()/watchdog_stop()

### ASSERT Macros
22 assertion macros in test_progs.h: ASSERT_TRUE/FALSE, ASSERT_EQ/NEQ/LT/LE/GT/GE, ASSERT_STREQ/STRNEQ/HAS_SUBSTR, ASSERT_MEMEQ, ASSERT_OK/ERR, ASSERT_NULL/OK_PTR/ERR_PTR, ASSERT_OK_FD/ERR_FD, ASSERT_FAIL. All call `test__fail()` on failure.

### SYS Macros
- `SYS(label, fmt, ...)` — run shell command, goto label on failure
- `SYS_FAIL(label, fmt, ...)` — expect command to fail
- `SYS_NOFAIL(fmt, ...)` — run command, ignore result (appends `>/dev/null 2>&1`)

### Flavors
Test binary name suffix determines flavor (e.g., `test_progs-bpf_gcc`). Calls `chdir(flavor)` to load correct BPF objects from flavor subdirectory. Used for GCC BPF backend testing, no-ALU32, cpuv4.

### Other Infrastructure
- `bpf_testmod.ko` — loadable kernel module for testing (testmod read/write triggers)
- `testing_helpers.c` — test loading, module management, JIT detection, xlated program dump
- `testing_prog_flags()` — probes kernel for supported test flags (BPF_F_TEST_RND_HI32, BPF_F_TEST_REG_INVARIANTS)
- `network_helpers` / `cgroup_helpers` / `trace_helpers` — shared test utilities
- Traffic monitor (`-m` flag) — packet capture during network tests
- JSON summary (`-J` flag) — structured test results output

## test_loader (BTF Annotation System)

### Architecture
Uses `btf_decl_tag` attributes (via `__attribute__((btf_decl_tag(...)))`) to embed test specifications directly in BPF program source. The test_loader reads BTF from compiled ELF, parses tags per-function, and drives load/verify/execute cycle.

### Annotations (bpf_misc.h)
| Macro | Purpose |
|-------|---------|
| `__success` / `__failure` | Expected load result (priv mode) |
| `__success_unpriv` / `__failure_unpriv` | Expected load result (unpriv mode) |
| `__msg("text")` | Expected verifier log substring (ordered) |
| `__not_msg("text")` | Verifier log should NOT contain this |
| `__xlated("pattern")` | Expected line in post-verifier disassembly |
| `__jited("pattern")` | Expected line in JIT disassembly (arch-specific) |
| `__retval(N)` | Execute via BPF_PROG_TEST_RUN, expect return value N |
| `__flag(FLAG)` | Set prog_flags (SLEEPABLE, STRICT_ALIGNMENT, etc.) |
| `__log_level(N)` | Verifier log level |
| `__description("text")` | Custom subtest name |
| `__arch_x86_64` etc. | Architecture filter |
| `__auxiliary` | Not a standalone test, loaded as helper |
| `__caps_unpriv(caps)` | Capabilities to retain in unpriv mode |
| `__stderr("text")` / `__stdout("text")` | Expected BPF stream output |
| `__linear_size(N)` | Non-linear skb linear area size |
| `__btf_path(path)` | Custom BTF for loading |

### Regex Support in Patterns
Patterns support inline regex via `{{...}}` delimiters. E.g., `__msg("r0 = {{[0-9]+}}")` matches any number. Extended POSIX regex inside brackets.

### Matching Algorithm
- Positive messages matched sequentially (each starts searching from end of previous match)
- Negative messages matched within span between surrounding positive messages
- `__jited`/`__xlated` use line-based matching (consecutive by default, `"..."` resets)

### Dual Mode (Priv/Unpriv)
Each test can run in privileged and/or unprivileged modes. Unpriv mode drops CAP_SYS_ADMIN, CAP_NET_ADMIN, CAP_PERFMON, CAP_BPF. Unpriv specs inherit from priv if not explicitly set.

### Usage: `RUN_TESTS(skel)`
Simple macro wrapping `test_loader__run_subtests()`. Iterates all programs in skeleton ELF, parses test specs from BTF, runs each non-auxiliary program as a subtest.

## BPF_PROG_TEST_RUN (Kernel Side)

### Purpose
Kernel-side infrastructure for executing BPF programs in a controlled environment without real events. Called via `BPF_PROG_TEST_RUN` bpf syscall command.

### Per-Type Implementations
| Function | Program Types |
|----------|--------------|
| `bpf_prog_test_run_skb` | SCHED_CLS, SCHED_ACT, CGROUP_SKB, LWT_*, SK_SKB, SK_MSG |
| `bpf_prog_test_run_xdp` | XDP |
| `bpf_prog_test_run_tracing` | TRACING (fentry/fexit/fmod_ret), LSM |
| `bpf_prog_test_run_raw_tp` | RAW_TRACEPOINT |
| `bpf_prog_test_run_syscall` | SYSCALL |
| `bpf_prog_test_run_flow_dissector` | FLOW_DISSECTOR |
| `bpf_prog_test_run_sk_lookup` | SK_LOOKUP |
| `bpf_prog_test_run_nf` | NETFILTER |

### Timer Infrastructure
`bpf_test_timer` manages repeated execution with RCU read lock, rescheduling support, and signal handling. Measures per-iteration time (returned as duration). **Gotcha:** `repeat > 1` reuses the same packet buffer without resetting bytes between iterations — data-modifying programs accumulate changes. XDP live mode only runs `init_callback` on first allocation. Use `repeat` for timing measurement only, not per-packet functional testing.

### XDP Test Run
Complex implementation with per-page frame management, multi-buffer support, live XDP actions (REDIRECT via devmap/cpumap), batch execution (32 frames/batch).

### SKB Test Run
Constructs a fake sk_buff from user data, runs through cls_bpf_classify or BPF_PROG_RUN, optionally supports live frames via netdev.

### Tracing/LSM Test Run
Minimal: calls BPF_PROG_RUN under rcu_read_lock with zeroed-out context (no real tracepoint data).

### Syscall Test Run
Direct execution with user-provided context (`ctx_in`/`ctx_out`), used by gen_loader.

**⚠ Gotcha:** `bpf_prog_test_run_syscall` silently accepts and ignores `kattr->test.cpu` — the field is validated for other run types but SYSCALL has no type-specific check (a silent-accept inconsistency).

### BPF Streams
Recent feature: `bpf_prog_stream_read` reads stdout/stderr streams from BPF programs (stream_id 1=stdout, 2=stderr). Used by test_loader `__stdout`/`__stderr` annotations.
