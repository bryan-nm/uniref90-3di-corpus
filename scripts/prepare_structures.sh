#!/usr/bin/env bash
# Tokenize a directory of structures with Foldseek and write paired FASTA ready for
# build_corpus.sh --append. By default keeps one representative per sequence cluster.
# usage: prepare_structures.sh [options] STRUCT_DIR OUT_PREFIX
#   --min-seq-id F     cluster identity threshold (default: 0.9)
#   --coverage F       cluster coverage threshold (default: 0.8)
#   --no-cluster       keep every structure
#   --id-prefix S      prefix of corpus IDs (default: EXT)
#   --cluster-prefix S prefix of cluster labels (default: Clu90)
#   --names MODE       stem (default) or uniprot-domain; see cluster_reps.py
#   --threads N        default: 8
# Requires foldseek on PATH (or FOLDSEEK=path), and mmseqs unless --no-cluster is given.
set -euo pipefail
export LC_ALL=C
scripts="$(cd "$(dirname "$0")" && pwd)"
foldseek=${FOLDSEEK:-foldseek}
min_id=0.9; cov=0.8; cluster=1; id_prefix=EXT; clu_prefix=Clu90; names=stem; threads=8
while [[ ${1:-} == --* ]]; do
    case $1 in
        --min-seq-id) min_id=$2; shift 2 ;;
        --coverage) cov=$2; shift 2 ;;
        --no-cluster) cluster=0; shift ;;
        --id-prefix) id_prefix=$2; shift 2 ;;
        --cluster-prefix) clu_prefix=$2; shift 2 ;;
        --names) names=$2; shift 2 ;;
        --threads) threads=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
dir=$1; out=$2

mkdir -p "$(dirname "$out")"
tmp=$(mktemp -d "$(dirname "$out")/tmp.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

"$foldseek" createdb "$dir" "$tmp/db" --threads "$threads" > /dev/null
"$foldseek" lndb "$tmp/db_h" "$tmp/db_ss_h" > /dev/null
"$foldseek" convert2fasta "$tmp/db" "$tmp/aa.raw" > /dev/null
"$foldseek" convert2fasta "$tmp/db_ss" "$tmp/3di.raw" > /dev/null
# Sort by name: Foldseek's output order, and so MMseqs2's choice of representatives, can vary.
paste - - < "$tmp/aa.raw" | sort -k1,1 | tr '\t' '\n' > "$tmp/aa.fasta"
paste - - < "$tmp/3di.raw" | sort -k1,1 | tr '\t' '\n' > "$tmp/3di.fasta"

if ((cluster)); then
    mmseqs easy-cluster "$tmp/aa.fasta" "$tmp/clu" "$tmp/mm" --min-seq-id "$min_id" -c "$cov" --cov-mode 0 \
        --threads "$threads" > /dev/null
else
    grep '^>' "$tmp/aa.fasta" | cut -c2- | awk '{print $1 "\t" $1}' > "$tmp/clu_cluster.tsv"
fi

python3 "$scripts/cluster_reps.py" "$tmp/clu_cluster.tsv" "$tmp/aa.fasta" "$tmp/3di.fasta" "$out" \
    --id-prefix "$id_prefix" --cluster-prefix "$clu_prefix" --names "$names"
