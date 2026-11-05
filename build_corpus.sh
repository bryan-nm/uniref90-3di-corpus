#!/usr/bin/env bash
# Build a paired AA/3Di FASTA corpus: one AFDB v6 entry per UniRef90 cluster, streamed
# without downloading the AFDB, plus any already-tokenized sequences given with --append.
# Finished steps are skipped on rerun. See README.md.
set -euo pipefail
scripts="$(cd "$(dirname "$0")" && pwd)/scripts"

usage() {
    cat << EOF
usage: build_corpus.sh [options]
  --work DIR        working directory for metadata and shards (default: work)
  --out PREFIX      writes PREFIX.aa.fasta and PREFIX.3di.fasta (default: WORK/corpus)
  --shards N        parallel streams, fixed by the first run (default: 16)
  --append PREFIX   append PREFIX.aa.fasta and PREFIX.3di.fasta; repeatable
  --base PREFIX     skip streaming and start from this existing corpus instead
EOF
}

work=work; out=""; shards=16; base=""; appends=()
while (($#)); do
    case $1 in
        --work) work=$2; shift 2 ;;
        --out) out=$2; shift 2 ;;
        --shards) shards=$2; shift 2 ;;
        --append) appends+=("$2"); shift 2 ;;
        --base) base=$2; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
out=${out:-$work/corpus}
mkdir -p "$work"

inputs=()
if [[ -n $base ]]; then
    inputs+=("$base")
else
    "$scripts/download_metadata.sh" "$work"

    selection=$work/selection_uniref90.tsv
    if [[ ! -s $selection ]]; then
        python3 "$scripts/build_selection.py" "$work/afdb241.index" "$work/afdb241.lookup" \
            "$work/idmapping_selected.tab.gz" "$selection.tmp" 2> "$work/selection.log"
        mv "$selection.tmp" "$selection"
    fi
    grep -v 'rows:' "$work/selection.log" 2> /dev/null || true

    if ! ls "$work"/selection_shards/sel_*.tsv > /dev/null 2>&1; then
        "$scripts/split_selection.sh" "$selection" "$work/selection_shards" "$shards"
    fi

    "$scripts/run_stream.sh" "$work/selection_shards" "$work/shards"
    for sel in "$work"/selection_shards/sel_*.tsv; do
        s=$(basename "$sel" .tsv)
        inputs+=("$work/shards/s${s#sel_}")
    done
fi
inputs+=(${appends[@]+"${appends[@]}"})

"$scripts/assemble_corpus.sh" "$out" "${inputs[@]}"
"$scripts/validate_pairs.sh" "$out"
