# BPF Selftests Infrastructure

Detailed reference for how BPF selftests are built, run, and configured in CI.

## Test Runners

Six test runners, executed inside a QEMU VM via `vmtest`:

| Runner | Binary | What it tests |
|--------|--------|--------------|
| `test_progs` | `test_progs` | Main BPF selftest suite (sequential) |
| `test_progs_parallel` | `test_progs -j` | Same tests, parallel execution |
| `test_progs_no_alu32` | `test_progs-no_alu32` | Tests without ALU32 (32-bit) mode |
| `test_progs_cpuv4` | `test_progs-cpuv4` | Tests with BPF CPU v4 ISA |
| `test_maps` | `test_maps` | BPF map tests (pinned to 4 CPUs via taskset) |
| `test_verifier` | `test_verifier` | BPF verifier tests |
| `test_progs-bpf_gcc` | `test_progs-bpf_gcc` | GCC-compiled BPF programs (optional, only if binary exists) |

## Allow/Deny List System

Two-layer system merging in-tree and CI-specific lists:

### Sources (in priority/merge order)
```
ALLOWLIST/DENYLIST files from:
  1. ${SELFTESTS_BPF}/ALLOWLIST          — in-tree (kernel source)
  2. ${SELFTESTS_BPF}/ALLOWLIST.${ARCH}  — in-tree, arch-specific
  3. ${VMTEST_CONFIGS}/ALLOWLIST          — CI-specific (vmtest repo)
  4. ${VMTEST_CONFIGS}/ALLOWLIST.${ARCH}  — CI-specific, arch-specific
  5. ${VMTEST_CONFIGS}/ALLOWLIST.${DEPLOYMENT} — deployment-specific
  6. ${VMTEST_CONFIGS}/ALLOWLIST.${KERNEL_TEST} — test-runner-specific
```
Same pattern for DENYLIST.

### Merge process
1. `run-vmtest.env` (in vmtest repo) defines the file arrays, exported as pipe-separated strings
2. `prepare-bpf-selftests.sh` calls `merge_test_lists_into()` which:
   - Concatenates all existing source files
   - Runs `normalize_bpf_test_names.py` to normalize test names
3. Result passed to test_progs via `-a@ALLOWLIST_FILE` and `-d@DENYLIST_FILE`

### Current denylists (vmtest repo)
- **DENYLIST** (global): `verif_scale_pyperf600`, `sockmap_basic/sockmap udp multi channels`, `map_kptr`
- **DENYLIST.aarch64**: `map_kptr/success-map`, `ns_xsk_*`, `send_signal`, `unpriv_bpf_disabled`
- **DENYLIST.s390x**: `arena_spin_lock`, `map_kptr/success-map`, `ns_xsk_*`, `res_spin_lock_stress`, `tc_edt`
- **DENYLIST.rc**: `send_signal/send_signal_nmi*` (AMD nested virt issue), `token/obj_priv_implicit_token_envvar`

### Current denylists (in-tree kernel)
- **DENYLIST**: `get_stack_raw_tp` (kernel warnings), `stacktrace_build_id*`, `task_fd_query_rawtp`, `varlen` — marked TEMPORARY
- **DENYLIST.asan**: `*arena*`, `task_local_data`, `uprobe_multi_test` (added by the ASAN series, 45897ced3c1d)
- **DENYLIST.riscv64**: exists
- **DENYLIST.s390x**: exists (in-tree)

### ASAN mode (`SELFTESTS_BPF_ASAN=true`)

The `test-progs-asan.yml` CI job builds with `ASAN=1` (adds `-fsanitize=address -fno-omit-frame-pointer`) and uses `DENYLIST.asan` via `${SELFTESTS_BPF_ASAN:+asan}` expansion in `run-vmtest.env`.

**Why arena tests are denied:** BPF arena memory lives in a shared user/kernel virtual region (`BPF_MAP_TYPE_ARENA`) obtained via mmap. ASAN's shadow memory model doesn't cover this region → false positives and missed real bugs → all `*arena*` tests excluded at runtime.

**ASAN error hook (`4c9d07865c06`):** `test_progs.c:1320-1324` defines `__asan_on_error()` (only under `__SANITIZE_ADDRESS__`) which calls `dump_crash_log()`. This restores stdout/stderr and dumps the test log through the normal test framework — ASAN errors land in the right test slot in CI output.

**Emil Tsalapatis's libarena series (v8, Apr 21, patchwork series 1083950, 8 patches, state: new):**
Introduces `libarena/` — a library for BPF arena-backed data structures with proper ASAN support:
- Patch 1/8: `#ifdef` guard for WRITE_ONCE macro in `bpf_atomic.h`
- Patch 2/8: Basic `libarena` scaffolding (new directory)
- Patch 3/8: Move arena-related headers (`bpf_arena_common.h`, etc.) into libarena
- Patch 4/8: Arena ASAN runtime — custom `__asan_poison_memory_region`/`__asan_unpoison_memory_region` tracking for arena allocs/frees
- Patch 5/8: ASAN build flags for libarena selftests
- Patch 6/8: Buddy allocator for libarena (arena-backed slab-style allocator)
- Patch 7/8: Selftests for the buddy allocator
- Patch 8/8: **"Reuse stderr parsing"** — hooks libarena ASAN errors into `dump_crash_log()` / `__asan_on_error()` from the existing ASAN series (NOT a parallel mechanism)

**Assessment:** Additive, no conflict with the existing ASAN series. When libarena lands, `*arena*` can be removed from `DENYLIST.asan` — arena ASAN coverage improves significantly.

## Build Pipeline

### Kernel build (`libbpf/ci/build-linux/`)
- **Inputs**: arch, toolchain (gcc/llvm), kbuild-output path
- **Config assembly**: Concatenates 6 config fragments:
  1. `tools/testing/selftests/bpf/config` — base BPF config
  2. `tools/testing/selftests/bpf/config.vm` — VM-specific
  3. `tools/testing/selftests/bpf/config.${ARCH}` — arch-specific
  4. `tools/testing/selftests/sched_ext/config` — sched_ext config
  5. `ci/vmtest/configs/config` — CI extras (e.g. `CONFIG_LIVEPATCH=y`)
  6. `ci/vmtest/configs/config.${ARCH}` — CI arch extras (e.g. KASAN for x86_64)
- Runs `make olddefconfig` then `make -j$(nproc*4) all`
- Smart rebuild: diffs config, only rebuilds if changed

### Selftest build (`libbpf/ci/build-selftests/`)
- **Inputs**: arch, toolchain, kernel-root
- Statically linked (`EXTRA_LDFLAGS=-static`)
- Uses clang/llc/llvm-strip from specified LLVM version
- Supports BPF GCC cross-compiler
- Runs: `make headers` → `make clean` → `make -j ...`

**EXTRA_CFLAGS / HOST_EXTRACFLAGS pass-through (landed 2026-06-14, series 9080b97689db..62617d28d9ae, Leo Yan):** The BPF tools build now appends `EXTRA_CFLAGS` to CFLAGS across bpftool, libbpf, `tools/bpf`, and selftests, plus `HOST_EXTRACFLAGS` for bootstrap/host tools (kept separate from HOST_CFLAGS). Lets builds inject extra compiler flags to mitigate a GCC 15 regression where a `{0}` initializer does not guarantee zeroing an entire union. Series also avoids static LLVM linking for cross builds (62617d28d9ae).

**Toolchain-floor policy (Alexei, 2026-06-30):** selftests are NOT disabled/skipped to accommodate old toolchains — raise the floor instead ("you have to upgrade your test environment. We won't be disabling tests because people still have old clang or old gcc"). Rejected (pw-bot: cr) skipping libarena when clang 19's BPF backend can't select the 32-bit arena cmpxchg ("unsupported atomic operation, please use 64 bit version"). Do not guard selftests behind toolchain-feature probes.

## VM Test Execution

### Flow
1. `run.sh` (the main action entry point):
   - Locates vmlinuz and vmlinux binaries
   - Links vmlinux to `/usr/lib/debug/boot/` for BTF
   - Sources `run-vmtest.env` to set up allow/denylists
   - Runs `prepare-bpf-selftests.sh` to merge lists
   - Generates vmtest TOML config (CPUs, memory, kernel args)
   - Calls `vmtest -c $VMTEST_TOML` (QEMU wrapper)
   - Collects exit status from `exitstatus` file
   - Prints test summary from JSON files

2. Inside VM (`run-bpf-selftests.sh`):
   - Sources helpers.sh for `foldable` and `read_lists`
   - Prints kernel config, allowlist, denylist
   - Runs test runners (all by default, or specific ones from args)
   - Each runner appends `name:exitcode` to `STATUS_FILE`
   - Veristat runs source configs from `run_veristat.*.cfg`

### VM config
- Default: 2 CPUs, 4G RAM
- Kernel args (run-vmtest-injected, VM-only): `panic=-1 sysctl.vm.panic_on_oom=1 hardlockup_all_cpu_backtrace=1 softlockup_all_cpu_backtrace=1 ... no5lvl` (`no5lvl` disables 5-level page tables in test VMs; libbpf/ci PR #225, merged ~2026-06-10)

## Workflow Structure (kernel-build-test.yml)

Orchestrates the full CI pipeline:
1. **build** → `kernel-build.yml`
2. **build-release** → `kernel-build.yml` with `-O2` (optional)
3. **test** → `kernel-test.yml` (matrix strategy, per-runner)
4. **veristat-kernel** → `veristat-kernel.yml`
5. **veristat-meta** → `veristat-meta.yml` (kernel-patches org only, uses AWS)
6. **veristat-scx** → `veristat-scx.yml`
7. **veristat-cilium** → `veristat-cilium.yml`
8. **gcc-bpf** → `gcc-bpf.yml` (x86_64 only)

## Key Helper Functions

- `foldable start/end` — GitHub Actions group folding
- `read_lists()` — merges files, strips comments (`#`), trims whitespace, joins with commas
- `platform_to_kernel_arch()` — maps platform names to kernel ARCH values
- `kernel_build_make_jobs()` — returns `min(nproc*4, MAX_MAKE_JOBS)`

## test_progs Parallel Mode Architecture

Parallel mode (`-j N`) forks N worker processes, connected to N dispatcher threads via Unix socket pairs (SOCK_SEQPACKET). Messages: MSG_DO_TEST, MSG_TEST_DONE, MSG_TEST_LOG, MSG_SUBTEST_DONE, MSG_EXIT.

### Network Namespace Isolation

Workers share the root network namespace. No per-worker `unshare(CLONE_NEWNET)`. Isolation is per-test via three mechanisms:

1. **`ns_` prefix convention** (~40 tests): `run_one_test()` detects `ns_` prefix, calls `netns_new(test_name, true)` which creates a named netns (`ip netns add`), switches into it via `setns()`, runs the test, then cleans up via `netns_free()` + `restore_netns()`. Safe because each test dispatched exactly once.

2. **Manual `netns_new()`/`make_netns()`**: Tests like `tc_redirect` create their own named netns (e.g., `ns_src`/`ns_fwd`/`ns_dst`). No collision because unique dispatch.

3. **`append_tid()` suffix**: Tests like `lwt_ip_encap`, `test_xdp_veth`, `xdp_vlan` append `gettid()` to netns names for extra uniqueness.

Tests needing exclusive global netns access use `serial_test_*` (e.g., `xdp_bonding`, `flow_dissector_reattach`). Named netns are globally visible in `/var/run/netns/` — no mount namespace isolation.

### Known Infrastructure Gaps (as of Mar 2026)

All confirmed unfixed in current bpf-next. No upstream patches or discussions addressing these.

1. **crash_handler doesn't terminate** — `SA_RESETHAND` resets to SIG_DFL but first SIGSEGV returns from handler. No `raise(signum)` or `_exit()`. Process continues after backtrace. (Eduard's watchdog sends SIGSEGV to terminate stuck tests, but crash_handler swallows it.)

2. **Silent test loss** — If worker crashes (SIGSEGV/SIGKILL), dispatch_thread hits socket EPIPE → `goto error` → sends MSG_EXIT to dead socket → returns. The test that was running is never marked `state->tested = true`, so it's invisible in results. `waitpid()` reap loop (line 1758) doesn't check `WIFSIGNALED()`. Eduard acknowledged this in watchdog commit message.

3. **Dispatch thread stall cascade** — Dead worker's dispatch thread sends MSG_EXIT to dead socket and returns without handling redistribution. Remaining workers continue, but any test dispatched to the dead worker is lost.

4. **Orphan workers on parent SIGTERM** — No SIGTERM handler, no `prctl(PR_SET_PDEATHSIG)`. Workers become orphans (ppid→1) on parent kill, linger until socket EPIPE or watchdog timeout (120s). BPF resources leak.

5. **No dmesg/taint detection** — `TAINT_WARN` from kernel WARNs doesn't affect exit code. Tests pass despite kernel warnings.

6. **Subtest filter silent-pass** — `-t 'test/nonexistent_sub'` runs the test with 0 subtests matched and exits 0. No `EXIT_NO_TEST` (exit 2) at subtest level. `-t ''` silently matches all tests (wildcard wrapping turns empty string into `**`). Stale subtest names in CI filter lists produce invisible false-green runs.

### Key Timeline

- **Nov 2024**: Eduard adds watchdog timer (`d9d4d127e813`). Acknowledges worker exhaustion gap.
- **Feb 2026**: ASAN SIGSEGV handler fix (`4c9d07865c06`). Refactors crash_handler but doesn't fix termination bug.
- **Mar 2026**: No one working on parallel mode reliability. Field is clear for patches.

### Upstream Submission Landscape

No overlapping work. Recent test_progs changes are test conversion (Alexis Lothoré), PID filtering (Sun Jian), and bug fixes (ASAN). The test_progs parallel mode bugs are novel findings suitable for a cohesive patch series.

## Partial Build Tolerance (Ricardo Marlière, Apr 2026)

10-patch series ([patchwork 1075942](https://patchwork.kernel.org/project/netdevbpf/list/?series=1075942)) addressing the "single failure breaks everything" problem. Currently v1, state: new.

### Problem

The current Makefile has zero error tolerance:
- **BPF compilation**: Any single `progs/*.c` → `.bpf.o` failure halts the entire build (standard make behavior)
- **Skeleton generation**: All `*.skel.h` files are prerequisites of all `.test.d` files — one skeleton failure blocks all test compilation
- **Linking**: test_progs links every `prog_tests/*.test.o` — if any fails to compile, link fails
- **Install**: `rsync` of `.bpf.o` files fails if any subdir is empty

This means kernel configs missing specific features (e.g., `CONFIG_NET=n`, `CONFIG_CGROUP=n`) break the entire selftest build, even though most tests would still work.

### Patch Breakdown

| # | Title | What it does |
|---|-------|-------------|
| 1 | Fall back to distro build directory for test_kmods | Uses host system's kernel build dir when in-tree KDIR unavailable |
| 2 | Tolerate BPF and skeleton generation failures | Likely wraps `.bpf.o`/`.skel.h` rules to continue on error |
| 3 | Avoid rebuilds when running emit_tests | Build optimization for test header regeneration |
| 4 | Make skeleton headers order-only prerequisites of .test.d | Breaks the hard dependency chain: skel failures don't block `.test.o` compilation |
| 5 | Tolerate test file compilation failures | `.test.o` failures don't halt build |
| 6 | Allow test_progs to link with a partial object set | Links only successfully-compiled test objects |
| 7 | Tolerate benchmark build failures | Same tolerance for benchmark binaries |
| 8 | Provide weak definitions for cross-test uprobe functions | `usdt_1.c`/`usdt_2.c` functions as `__weak` so test_progs links even without them |
| 9 | Skip tests whose objects were not built | Runtime: test_progs detects missing BPF objects and auto-skips |
| 10 | Tolerate missing files during install | `rsync` doesn't fail on empty/missing dirs |

### Key Design Insight

The existing `__weak` extern pattern in `test_progs.c` already handles partial test functions gracefully (test entry with NULL function pointer = skip). Ricardo's series extends this tolerance to the build system: partially-compiled BPF objects, partially-linked test_progs binary, and runtime skip for tests whose BPF objects don't exist.

### CI Impact

This is directly relevant to BPF CI:
- Enables running selftests on non-standard kernel configs (embedded, minimal, RT)
- Reduces CI flakiness from unrelated build failures
- Enables incremental selftest builds (compile only what changed)
- Addresses a known pain point: cross-arch builds where some features are unavailable

## Build System Quirks

**UAPI header deps untracked:** `.bpf.o` build rules don't list UAPI headers (`tools/include/uapi/`) as prerequisites and don't use `-MMD` for compiler-generated dep files. Touching `tools/include/uapi/linux/bpf.h` produces silently stale BPF objects. 379/~500 progs include `<linux/bpf.h>`. Fix: add `-MMD -MP -MF $2.d` to `CLANG_BPF_BUILD_RULE` + include generated `.d` files. CI unaffected (clean builds), local dev affected.

**`progs/*.h` glob is overly broad:** All ~500 BPF objects rebuild when any header in `progs/` changes, even if only one program uses it. `-MMD` would fix both over- and under-tracking.

**Pinned file cleanup gap:** 13 tests pin maps/links to `/sys/fs/bpf/`. All cleanup is per-test (`out:` labels). `crash_handler` does zero BPF cleanup. Worker crash orphans pinned files → `-EEXIST` on re-run. Only 2/13 tests have defensive pre-unlink.

## Writing selftests — conventions

Condensed conventions for authoring selftests (`tools/testing/selftests/bpf`), from upstream review practice — what keeps a new test idiomatic and past review:

- **Assertions:** use the modern `ASSERT_*()` macros (`ASSERT_OK`, `ASSERT_EQ`, `ASSERT_OK_PTR`, `ASSERT_OK_FD`); `CHECK()`/`CHECK_FAIL()` are deprecated. Don't force a `CHECK→ASSERT` migration on a file that's *uniformly* `CHECK()` for a small change.
- **Determinism:** poll for the actual event, never fixed sleeps; don't hardcode magic resources (bind to port 0, resolve `if_nametoindex("lo")`); keep pass/fail on correctness only (timing is informational). Be **bisect-safe** — assert-and-fail cleanly, never panic the kernel.
- **Skip, don't fail,** when a required feature/kfunc/config is unavailable — and add the needed `CONFIG` to `tools/testing/selftests/bpf/config` so CI enables it.
- **Verifier tests:** write accept/reject tests declaratively via `test_loader` annotations (`__description`, `__success __retval(N)` / `__failure __msg("…")`, `__failure_unpriv`) with a `SEC()`/`__naked` program. Match volatile fields (regs/offsets) with the `{{…}}` regex form, never hardcoded; gate arch-specific expectations with `__arch("…")` and JIT-dependent ones with `__load_if_JITed()`.
- **Skeleton API:** `NAME__open_and_load()` checked with `ASSERT_OK_PTR`, access via `bpf_map__fd()` / `skel->bss`, free with `NAME__destroy()`; register subtests with `test__start_subtest()`.
- **Hygiene:** ship a selftest/reproducer with the fix it covers; reset shared/global state between runs; init fds to `-1` and guard `close()` with `fd >= 0`; every `DENYLIST.<arch>` entry needs a trailing "why" comment and must be removed once support lands. Deflake rather than tolerate flakes.
- **Style:** modern kernel multi-line comment style (`/*` on its own line); reverse-xmas-tree local declarations; extract shared test helpers into a header rather than copy-pasting a logic block.
