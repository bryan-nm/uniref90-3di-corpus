#!/usr/bin/env bash
# Split an offset-sorted selection TSV into N shard files of roughly equal byte span
# (the span each stream_pairs.py process must download), in one streaming pass.
# usage: split_selection.sh SELECTION_TSV OUT_DIR N
set -euo pipefail
sel=$1; out=$2; n=$3
mkdir -p "$out"
rm -f "$out"/sel_*.tsv
end=$(tail -1 "$sel" | awk -F'\t' '{print $2 + $3}')
awk -F'\t' -v n="$n" -v end="$end" -v out="$out" '{
    s = int($2 * n / end); if (s >= n) s = n - 1
    f = sprintf("%s/sel_%02d.tsv", out, s)
    if (f != cur) { if (cur != "") close(cur); cur = f }
    print >> f
}' "$sel"
wc -l "$out"/sel_*.tsv | tail -1
