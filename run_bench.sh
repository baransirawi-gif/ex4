#!/usr/bin/env bash
# run_bench.sh - correctness + timing harness for the project pintool.
#
# For each benchmark: run natively, under the ORIGINAL bprofile-with-gearing.so
# (baseline) and under project.so, N times each. Captures the tool's printed
# "took: X seconds" number and wall time, and diffs the program's output
# against the native reference. Appends rows to results.csv:
#     benchmark,tool,config,run,seconds,wall,correct
#
# Usage:
#   PIN_ROOT=/path/to/pin ./run_bench.sh [-n N] [-b "bzip2 cc1 ..."] \
#        [-t "native baseline project"] [-c config_name] [-- extra project knobs]
#
# Examples:
#   ./run_bench.sh -n 5                                  # full table
#   ./run_bench.sh -n 1 -b "bzip2 cc1" -t project        # quick correctness check
#   ./run_bench.sh -t project -c nodevirt -- -no_devirt  # ablation row
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
BENCH_DIR=${BENCH_DIR:-$HERE/bench}
PIN=${PIN_ROOT:?set PIN_ROOT to the Pin kit}/pin
BASE_SO=${BASE_SO:-$HERE/baseline/obj-intel64/bprofile-with-gearing.so}
PROJ_SO=${PROJ_SO:-$HERE/obj-intel64/project.so}
N=5
BENCHES="bzip2 cc1 sgcc_base sgcc_peak cpugcc_r_base"
TOOLS="native baseline project"
CONFIG=default
CSV=${CSV:-$HERE/results.csv}
TIMEOUT=${TIMEOUT:-600}

while [ $# -gt 0 ]; do
  case $1 in
    -n) N=$2; shift 2;;
    -b) BENCHES=$2; shift 2;;
    -t) TOOLS=$2; shift 2;;
    -c) CONFIG=$2; shift 2;;
    --) shift; break;;
    *) echo "unknown arg $1"; exit 1;;
  esac
done
EXTRA_KNOBS=("$@")

REF=$HERE/.ref          # native reference outputs
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$REF"
[ -f "$CSV" ] || echo "benchmark,tool,config,run,seconds,wall,correct" > "$CSV"

# Command line of each benchmark. OUT is the file the program writes, which is
# diffed against the native run. bzip2 writes to stdout (-c) so the input file
# is never modified or deleted.
bench_cmd() {  # $1=bench $2=outfile
  case $1 in
    bzip2)          echo "$BENCH_DIR/bzip2 -c $BENCH_DIR/input-long.txt";;   # stdout -> $2
    cc1)            echo "$BENCH_DIR/cc1 $BENCH_DIR/200.i -o $2";;
    sgcc_base)      echo "$BENCH_DIR/sgcc_base.mytest-m64 $BENCH_DIR/200.i -o $2";;
    sgcc_peak)      echo "$BENCH_DIR/sgcc_peak.mytest-m64 $BENCH_DIR/200.i -o $2";;
    cpugcc_r_base)  echo "$BENCH_DIR/cpugcc_r_base.mytest-m64 $BENCH_DIR/200.i -o $2";;
  esac
}
stdout_is_output() { [ "$1" = bzip2 ]; }

run_one() {  # $1=bench $2=tool $3=run#
  local b=$1 tool=$2 r=$3 out=$WORK/$b.$tool.out log=$WORK/$b.$tool.log
  local cmd; cmd=$(bench_cmd "$b" "$out")
  local pre=()
  case $tool in
    native)   pre=();;
    baseline) pre=("$PIN" -t "$BASE_SO" --);;
    project)  pre=("$PIN" -t "$PROJ_SO" "${EXTRA_KNOBS[@]}" --);;
  esac
  rm -f "$out"
  # Run from WORK so bprofile.out etc. do not litter the repo.
  local s e rc
  s=$(date +%s.%N)
  if stdout_is_output "$b"; then
    (cd "$WORK" && timeout "$TIMEOUT" "${pre[@]}" $cmd > "$out" 2> "$log"); rc=$?
  else
    (cd "$WORK" && timeout "$TIMEOUT" "${pre[@]}" $cmd > /dev/null 2> "$log"); rc=$?
  fi
  e=$(date +%s.%N)
  local wall; wall=$(echo "$e - $s" | bc)
  local took; took=$(grep -oE 'took: [0-9.e+-]+ seconds' "$log" | tail -1 | awk '{print $2}')
  [ "$tool" = native ] && took=$wall
  [ -z "$took" ] && took=NA

  local ok=1
  if [ "$tool" = native ] && [ ! -f "$REF/$b.out" ]; then
    cp "$out" "$REF/$b.out"
  fi
  if [ $rc -ne 0 ] || ! cmp -s "$out" "$REF/$b.out"; then ok=0; fi
  if [ $ok = 0 ]; then
    mkdir -p "$HERE/failures"
    cp "$log" "$HERE/failures/$b.$tool.$CONFIG.$r.log" 2>/dev/null
    echo "  !! $b/$tool/$CONFIG run $r: rc=$rc, output $( [ -f "$out" ] && echo differs || echo missing ) (log in failures/)" >&2
  fi
  echo "$b,$tool,$CONFIG,$r,$took,$wall,$ok" >> "$CSV"
  printf '  %-14s %-9s %-10s run %d  took=%-10s wall=%-8.2f correct=%d\n' "$b" "$tool" "$CONFIG" "$r" "$took" "$wall" "$ok"
}

for b in $BENCHES; do
  # Always make sure the native reference exists before any tool run.
  if [ ! -f "$REF/$b.out" ] && [[ " $TOOLS " != *" native "* ]]; then
    echo "creating native reference for $b"; run_one "$b" native 0 >/dev/null
  fi
  for tool in $TOOLS; do
    for r in $(seq 1 "$N"); do run_one "$b" "$tool" "$r"; done
  done
done

# Median per (benchmark, tool, config) over the rows just written.
python3 - "$CSV" <<'EOF'
import csv, sys, statistics as st
rows = list(csv.DictReader(open(sys.argv[1])))
groups = {}
for r in rows:
    k = (r['benchmark'], r['tool'], r['config'])
    groups.setdefault(k, []).append(r)
print(f"\n{'benchmark':14} {'tool':9} {'config':12} {'n':>3} {'median took':>12} {'median wall':>12} {'correct':>8}")
for k, rs in groups.items():
    t = [float(r['seconds']) for r in rs if r['seconds'] != 'NA']
    w = [float(r['wall']) for r in rs]
    ok = sum(int(r['correct']) for r in rs)
    print(f"{k[0]:14} {k[1]:9} {k[2]:12} {len(rs):3} {st.median(t) if t else float('nan'):12.3f} {st.median(w):12.3f} {ok:>4}/{len(rs)}")
EOF
