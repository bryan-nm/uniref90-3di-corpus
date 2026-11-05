#!/usr/bin/env bash
# Check a paired corpus with streaming passes: headers and lengths agree in every pair, 3Di uses
# only the 20 valid letters, every record has two lines, and IDs are unique.
# usage: validate_pairs.sh PREFIX
# The uniqueness check sorts on disk next to the corpus, using at most 2 GB of memory.
set -euo pipefail
export LC_ALL=C
prefix=$1

paste <(paste - - < "$prefix.aa.fasta") <(paste - - < "$prefix.3di.fasta") | awk -F'\t' '
    {
        n++; residues += length($2)
        if ($1 != $3) header++
        if (length($2) != length($4)) len++
        if ($4 ~ /[^ACDEFGHIKLMNPQRSTVWY]/) alphabet++
        if (substr($1, 1, 1) != ">" || NF != 4) format++
    }
    END {
        printf "records=%d mean_len=%.1f header_mismatch=%d length_mismatch=%d bad_3di=%d format_errors=%d\n",
            n, (n ? residues / n : 0), header, len, alphabet, format
        exit (n == 0 || header + len + alphabet + format > 0)
    }'

tmp=$(mktemp -d "$(dirname "$prefix")/sort.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
dups=$(grep '^>' "$prefix.aa.fasta" | cut -d' ' -f1 | sort -S 2G -T "$tmp" | uniq -d | wc -l | tr -d ' ')
echo "duplicate_ids=$dups"
[[ $dups -eq 0 ]]
