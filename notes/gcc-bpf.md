# GCC BPF CI

GCC BPF backend support in upstream BPF CI. Ihor Solodrai owns this integration.

## Architecture

```
theihor/gcc-bpf (GitHub releases)
  → downloaded by CI as pre-built .tar.zst
  → gcc-bpf.yml workflow (build-only, no VM execution)
  → test_progs-bpf_gcc binary compiled but NOT run
```

Two repos carry identical config:
- `kernel-patches/vmtest` — production CI (CodeBuild runners)
- `libbpf/ci` — reusable CI components (GitHub-hosted runners)

## Current State (Apr 2026)

- **Build-only**: `gcc-bpf.yml` compiles `test_progs-bpf_gcc` every PR. Does NOT run tests.
- **Runner disabled**: `test_progs-bpf_gcc` commented out in `matrix.py` (line 191-194)
  - Reason: too many failing tests ([lore thread](https://lore.kernel.org/bpf/87bjw6qpje.fsf@oracle.com/))
- **Denylist**: 904 entries in `DENYLIST.test_progs-bpf_gcc`
  - 425 verifier tests (47%)
  - ~100 dynptr/iterator/kfunc tests
  - ~8 CO-RE tests (most CO-RE bypassed via `-DBPF_NO_PRESERVE_ACCESS_INDEX`)
  - 189 unique top-level test names out of ~1394 total test functions
- **x86_64 only**: GCC BPF CI gated on `arch == 'x86_64' && !is_netdev`

## Build Rules

Makefile (`tools/testing/selftests/bpf/Makefile`):
- `BPF_GCC ?= $(shell command -v bpf-gcc;)` — auto-detect or CI override
- `GCC_BPF_BUILD_RULE`: `$(BPF_GCC) -DBPF_NO_PRESERVE_ACCESS_INDEX -Wno-attributes -O2 -c`
- No `--target=bpf` (GCC BPF is a native cross-compiler)
- No `-mcpu=v3` flag
- `-Wno-error` for 5 btf_dump tests with GCC anonymous struct warnings

## Key Gaps vs Clang

1. **No CO-RE** — `__builtin_preserve_access_index` unsupported → `-DBPF_NO_PRESERVE_ACCESS_INDEX`
2. **Atomics** — limited BPF atomic instruction support
3. **Exceptions/dynptrs/iterators** — all denied, likely compiler codegen issues
4. **Struct ops** — partially denied
5. **Inline asm** — Cupertino Miranda adapted operand constraints (d9075ac631ce)

## GCC BPF Compiler Distribution

- Repo: `theihor/gcc-bpf`
- Published as tagged `.tar.zst` releases
- CI downloads latest release via `download-gh-release.sh`
- Based on GCC trunk with BPF target patches

## Key People

| Person | Role | Affiliation |
|--------|------|------------|
| Ihor Solodrai | CI owner, gcc-bpf releases | Meta |
| Vineet Gupta | gcc-bpf improvements (compiler + verifier mismatch) | Meta |
| Jose E. Marchesi | GCC BPF backend maintainer | Oracle |
| Cupertino Miranda | GCC BPF backend contributor | Oracle |
| Sam James | GCC compatibility fixes | Gentoo |

**Note on Vineet Gupta:** Working on gcc-bpf from the compiler side (not CI). Focus:
- ABI incompatibility with LLVM for narrow-type args/return values (GCC PR/124171, PR/124419) — different calling conventions produce verifier false failures
- Bitfield codegen bugs (PR/123894, PR/123962)
- Goal: make gcc first-class BPF citizen; attending weekly community gcc-bpf meetup
- North Star: build real-world projects (sched_ext, Cilium, pyperf, strobelight) with gcc-bpf

## Recent Activity

- **GCC 16 fixes** (Jan 2026): Jose Marchesi — function attribute positioning, `-Wunused-but-set-variable` adaptation (2-patch series, merged)
- **Inline asm operand constraints** (Dec 2025): Cupertino Miranda — GCC compatibility for verifier selftests
- **Makefile regex matching** (Dec 2025): Cupertino Miranda — regex-based test selection for BPF selftests
- **preserve_field_info** (Aug 2025): Sam James — GCC compatibility for perf BPF

## Path Forward

The CI infrastructure is fully in place. When GCC BPF gains enough feature parity:
1. Uncomment `test_progs-bpf_gcc` in `matrix.py`
2. Trim denylist as tests start passing
3. Eventually add VM-based test execution

Key upstream blockers: CO-RE support (`preserve_access_index`), atomics, and verifier test compilation.

## See Also

- see ci-pipeline.md for overall BPF CI architecture
