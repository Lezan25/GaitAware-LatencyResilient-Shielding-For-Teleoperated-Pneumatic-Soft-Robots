#!/usr/bin/env bash
# Reproduces every result in README.md.
#
#   ./run.sh [proofs|theorems|checks|sim|sweep|sens|summary|all]     (default: all)
#
# VERIFYTA=/path/to/verifyta (default: verifyta on PATH), JOBS=4 parallel runs.
# Per-shield and per-setting copies of the models are written to tmp/; verifyta
# output (with counterexample traces) to results/, and an overview to results/summary.md.
set -u
cd "$(dirname "$0")"
VERIFYTA="${VERIFYTA:-verifyta}"
JOBS="${JOBS:-4}"
OUT=results; TMP=tmp
mkdir -p "$OUT" "$TMP"
SHIELDS="S1 S2 S3 S4 S5 S6 S7"

shield() {
  case $1 in
    S1) echo CHAMBER_AWARE=false DELAY_AWARE=false HANDBACK=HANDBACK_LATE  AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S2) echo CHAMBER_AWARE=true  DELAY_AWARE=false HANDBACK=HANDBACK_LATE  AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S3) echo CHAMBER_AWARE=false DELAY_AWARE=true  HANDBACK=HANDBACK_LATE  AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S4) echo CHAMBER_AWARE=true  DELAY_AWARE=true  HANDBACK=HANDBACK_LATE  AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S5) echo CHAMBER_AWARE=true  DELAY_AWARE=true  HANDBACK=HANDBACK_EARLY AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S6) echo CHAMBER_AWARE=true  DELAY_AWARE=true  HANDBACK=HANDBACK_GAIT  AVOIDANCE=AVOID_MAX_CLEARANCE ;;
    S7) echo CHAMBER_AWARE=true  DELAY_AWARE=true  HANDBACK=HANDBACK_GAIT  AVOIDANCE=AVOID_GAIT_AWARE ;;
  esac
}

# copy NAME FROM CONSTANT=VALUE... : tmp/NAME.xml with constants changed
copy() {
  local name=$1 from=$2 kv f="$TMP/$1.xml"; shift 2
  cp "$from" "$f"
  for kv in "$@"; do
    sed -E "s/(const +(int|bool) +${kv%%=*} *= *)[^;]+;/\1${kv#*=};/" "$f" > "$f.t" && mv "$f.t" "$f"
    grep -Eq "const +(int|bool) +${kv%%=*} *= *${kv#*=};" "$f" || { echo "no constant ${kv%%=*} in $from" >&2; exit 1; }
  done
}
# run NAME [QUERYFILE] : verifyta on tmp/NAME.xml, shortest counterexample traces
run() {
  echo "  $1"
  if [ -n "${2:-}" ]; then echo "$2" > "$OUT/$1.query"; else rm -f "$OUT/$1.query"; fi
  "$VERIFYTA" -u -q -t1 "$TMP/$1.xml" ${2:+"$2"} > "$OUT/$1.txt" 2>&1
}
spawn() { while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done; "$@" & }

proofs() {
  echo "proofs"
  for s in $SHIELDS; do
    copy "proof_$s" proofs/shield_proof.xml $(shield $s)
    case $s in S1|S3) q=queries/proof_chamber_naive.q ;; *) q=queries/proof.q ;; esac
    spawn run "proof_$s" "$q"
  done
}
theorems() {
  echo "theorems"
  for t in T1_filter T2_executor T3_handback; do copy "theorem_$t" "proofs/$t.xml"; spawn run "theorem_$t"; done
}
checks() {
  echo "checks"
  copy check_T1_delay_naive  proofs/T1_filter.xml   DELAY_AWARE=false
  copy check_T1_range1       proofs/T1_filter.xml   SENSOR_RANGE=1
  copy check_T3_early_rule   proofs/T3_handback.xml HANDBACK=HANDBACK_EARLY
  copy check_T1_gap1         proofs/T1_filter.xml   MIN_MOVE_GAP=1
  for v in SENSOR_RANGE=2 SENSOR_RANGE=4 MIN_MOVE_GAP=2 MIN_MOVE_GAP=4; do
    n=$(echo "$v" | tr -d '=_' | tr 'A-Z' 'a-z')
    copy "check_T1_$n" proofs/T1_filter.xml "$v"
    copy "check_T3_$n" proofs/T3_handback.xml "$v"
  done
  for f in "$TMP"/check_*.xml; do spawn run "$(basename "$f" .xml)"; done
}
sim() {
  echo "sim"
  for s in $SHIELDS; do copy "sim_$s" shield.xml $(shield $s); spawn run "sim_$s"; done
}
sweep() {
  echo "sweep"
  for n in 1 2 4 5; do
    for s in S4 S5 S6 S7; do copy "sweep_${s}_n$n" shield.xml $(shield $s) NUM_OBSTACLES=$n; spawn run "sweep_${s}_n$n"; done
  done
}
sens() {
  echo "sens"
  for v in SENSOR_RANGE=2 SENSOR_RANGE=4 MIN_MOVE_GAP=2 MIN_MOVE_GAP=4 \
           KEEP_DIRECTION_WEIGHT=0 KEEP_DIRECTION_WEIGHT=324 TURN_ONE_IN=12 TURN_ONE_IN=48; do
    n=$(echo "$v" | tr -d '=_' | tr 'A-Z' 'a-z')
    for s in S4 S5 S6 S7; do copy "sens_${s}_$n" shield.xml $(shield $s) "$v"; spawn run "sens_${s}_$n"; done
  done
}

formulas() {   # formulas of run NAME, in order
  if [ -f "$OUT/$1.query" ]; then grep -v '^ *$' "$(cat "$OUT/$1.query")"
  else grep -o '<formula>[^<]*</formula>' "$TMP/$1.xml" | sed -e 's/<[/]*formula>//g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'; fi
}
results() {    # result of each formula, in order
  awk '/^Verifying formula/ {n++} /Formula is satisfied/ {r[n]="satisfied"} /Formula is NOT satisfied/ {r[n]="NOT satisfied"}
       /States stored/ {s[n]=$5} /runs\) Pr\(/ {p=$0; sub(/^.*\) in /,"",p); r[n]="Pr in " p}
       /E\(max\) =/ {e=$0; sub(/^.*E\(max\) = /,"",e); r[n]=e}
       END {for (i=1;i<=n;i++) print r[i] (s[i] ? " (" s[i] " states)" : "")}' "$OUT/$1.txt"
}
summary() {
  {
    echo "# Results ($(date +%F))"; echo
    echo "| run | query | result |"; echo "|---|---|---|"
    for f in "$OUT"/*.txt; do
      b=$(basename "$f" .txt)
      paste -d'|' <(formulas "$b") <(results "$b") | while IFS='|' read -r fo re; do echo "| $b | \`$fo\` | $re |"; done
    done
  } > "$OUT/summary.md"
  echo "wrote $OUT/summary.md"
}

case "${1:-all}" in
  proofs) proofs ;; theorems) theorems ;; checks) checks ;; sim) sim ;; sweep) sweep ;; sens) sens ;;
  summary) summary; exit 0 ;;
  all) proofs; theorems; checks; sim; sweep; sens ;;
  *) echo "usage: $0 [proofs|theorems|checks|sim|sweep|sens|summary|all]"; exit 1 ;;
esac
wait
summary
