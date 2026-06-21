#!/usr/bin/env bash
# Acceptance check for ecdict-lite (gate B/I): a short MUST-PASS list (build fails if any
# missing) + a larger spot-check list reporting a hit rate.
set -u
DB="${1:-$(dirname "$0")/build/ecdict-lite.sqlite}"
if [ ! -f "$DB" ]; then echo "lite DB not found: $DB"; exit 1; fi

MUST=(resilient ubiquitous mitigate ambiguous sophisticated "take off" "look up" "set up" studies ran better best went children running)

SPOT=(the be have do say get make go know take see come think look want give use find tell ask
      work seem feel try leave call good new first last long great little own other old right big
      high different small large next early young important few public bad same able
      analyze benefit conclude consequence demonstrate emphasize establish illustrate
      negotiate participate phenomenon precise reluctant significant strategy
      "give up" "carry out" "point out" "find out" "deal with" "depend on")

fail=0
echo "=== MUST-PASS (build blocker) ==="
for w in "${MUST[@]}"; do
  t=$(sqlite3 "$DB" "SELECT coalesce(translation,'') FROM stardict WHERE word=lower('$w') LIMIT 1;")
  if [ -z "$t" ]; then echo "  FAIL  $w"; fail=1; else echo "  ok    $w"; fi
done

echo ""
echo "=== SPOT-CHECK (hit rate, informational) ==="
hits=0; total=0
miss=()
for w in "${SPOT[@]}"; do
  total=$((total+1))
  t=$(sqlite3 "$DB" "SELECT 1 FROM stardict WHERE word=lower('$w') LIMIT 1;")
  if [ -n "$t" ]; then hits=$((hits+1)); else miss+=("$w"); fi
done
echo "  hit rate: $hits/$total"
[ ${#miss[@]} -gt 0 ] && echo "  missed: ${miss[*]}"

echo ""
if [ $fail -eq 0 ]; then echo "MUST-PASS: ALL GOOD"; else echo "MUST-PASS: FAILURES (build blocked)"; fi
exit $fail
