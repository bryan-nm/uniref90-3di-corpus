#!/usr/bin/env bash
# Concatenate paired FASTA inputs, in order, into one corpus.
# usage: assemble_corpus.sh OUT_PREFIX INPUT_PREFIX...
# Each input is a prefix with .aa.fasta and .3di.fasta files: a stream shard, an existing
# corpus, or tokenized structures from prepare_structures.sh.
set -euo pipefail
out=$1; shift

for prefix in "$@"; do
    [[ $prefix != "$out" ]] || { echo "input and output are both $out" >&2; exit 1; }
    for t in aa 3di; do
        [[ -s $prefix.$t.fasta ]] || { echo "missing or empty: $prefix.$t.fasta" >&2; exit 1; }
    done
done

mkdir -p "$(dirname "$out")"
for t in aa 3di; do
    for prefix in "$@"; do
        cat "$prefix.$t.fasta"
    done > "$out.$t.fasta.tmp"
    mv "$out.$t.fasta.tmp" "$out.$t.fasta"
done
