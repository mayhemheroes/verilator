#!/usr/bin/env bash
#
# mayhem/test.sh — RUN Verilator's functional oracle (built by mayhem/build.sh as
# /mayhem/verilator_bin_test, a clean non-sanitized front-end). This is a known-answer /
# golden-content test: elaborate a small Verilog design with --json-only and ASSERT that the
# emitted AST JSON contains the expected module, nets and node types.
#
# A no-op / exit(0) sabotage of verilator produces no (or empty) JSON → the greps fail →
# this oracle FAILS. "ran and exited 0" is NOT sufficient.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"
export VERILATOR_ROOT="$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

VBIN=/mayhem/verilator_bin_test
if [ ! -x "$VBIN" ]; then
  echo "FATAL: $VBIN missing — mayhem/build.sh did not produce the test binary" >&2
  emit_ctrf "verilator-xml-oracle" 0 1
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/adder.v" <<'EOF'
module adder (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [4:0] sum
);
   assign sum = a + b;
endmodule
EOF

passed=0; failed=0
run_case() { # <name> <predicate-cmd...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $name"; passed=$((passed+1))
  else
    echo "FAIL: $name"; failed=$((failed+1))
  fi
}

# Elaborate → AST JSON dump (--json-only is the modern replacement for the removed --xml-only).
JSON="$WORK/out/adder.tree.json"
if "$VBIN" --json-only --Mdir "$WORK/out" --json-only-output "$JSON" "$WORK/adder.v" >"$WORK/log" 2>&1; then
  echo "PASS: verilator --json-only exits 0 on valid design"; passed=$((passed+1))
else
  echo "FAIL: verilator --json-only failed on a valid design"; cat "$WORK/log" >&2; failed=$((failed+1))
fi

# Assert the JSON AST was produced and carries the expected structure (golden content). Node
# objects are `{"type":"<TYPE>","name":"<name>",...}`; a valid parse of `adder` MUST contain a
# MODULE node named "adder" and the declared nets.  A no-op / exit(0) sabotage emits no JSON →
# these greps fail → the oracle fails.
run_case "json file produced"        test -s "$JSON"
run_case "json is a JSON object"     bash -c 'head -c1 "'"$JSON"'" | grep -q "{"'
run_case "json has a MODULE node"    grep -q '"type":"MODULE"' "$JSON"
run_case "json names module 'adder'" grep -q '"name":"adder"'  "$JSON"
run_case "json has net 'a'"          grep -q '"name":"a"'      "$JSON"
run_case "json has net 'sum'"        grep -q '"name":"sum"'    "$JSON"
run_case "json has a VAR node"       grep -q '"type":"VAR"'    "$JSON"

# Negative case: a syntactically broken design MUST be REJECTED (non-zero exit), proving the
# front-end actually parses rather than rubber-stamping input.
cat > "$WORK/bad.v" <<'EOF'
module bad ( input wire x );
   assign  = x
endmodule
EOF
if "$VBIN" --json-only --Mdir "$WORK/badout" --json-only-output "$WORK/bad.tree.json" "$WORK/bad.v" >/dev/null 2>&1; then
  echo "FAIL: verilator accepted a syntactically invalid design"; failed=$((failed+1))
else
  echo "PASS: verilator rejects a syntactically invalid design"; passed=$((passed+1))
fi

emit_ctrf "verilator-json-oracle" "$passed" "$failed"
