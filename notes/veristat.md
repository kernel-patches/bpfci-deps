# veristat — verifier performance & regression tracking

`veristat` loads BPF programs through the kernel verifier and reports per-program stats — most
importantly the **verdict** (does it load?) and the **state count** (how much work the verifier
did). BPF CI uses it to catch two things a functional test won't: a program that newly **fails to
load**, and a change that makes the verifier do materially **more work** (a states/instructions
regression).

Source: `tools/testing/selftests/bpf/veristat.c` (built alongside the selftests).

## The tool

```
veristat [opts] <file.bpf.o | dir> ...
```

- `-o csv` — CSV output; `-e file,prog,verdict,states` selects columns (also `insns`, `duration`, …).
- `-q` — quiet (suppress progress).
- `-C <base.csv> <new.csv>` / `--compare` — diff two runs, showing per-program deltas.
- `-f <filter>` — select programs; `-l` sets verifier log level; `-t` test mode.
- Key fields: `verdict` (success/failure) and `states` (number of verifier states explored — the
  performance proxy).

Typical local use: build the selftests, run `veristat -o csv` on the `.bpf.o` files before and
after your change, and `--compare` the two CSVs to see which programs moved.

## How BPF CI uses it

Four **corpora** are loaded through the verifier inside a vmtest VM, one workflow each
(`veristat-{kernel,meta,scx,cilium}.yml`):

| Corpus | Source |
|--------|--------|
| kernel | in-tree `*.bpf.o` built from the selftests |
| meta   | a corpus of BPF objects synced from S3 (kernel-patches org only; needs AWS creds) |
| scx    | sched_ext schedulers, built for the run |
| cilium | Cilium's BPF objects from a release tarball |

**Baseline & compare:**
- On **push** to a base branch (`bpf`, `bpf-next`, …) the veristat CSV is cached — pushes
  establish the baseline.
- On a **PR** the baseline CSV is restored and `veristat --compare` runs (`veristat_compare.py`).

**Signal:** the threshold is 0, so *any* state-count delta is reported in the job summary — but the
job **fails only on a new success→failure regression** (a program that used to verify and now does
not). Pure state-count increases are surfaced for a human to judge, not treated as hard failures.

See ci-pipeline.md for where veristat sits in the overall workflow.
