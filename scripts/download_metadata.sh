#!/usr/bin/env bash
# Fetch the AFDB v6 index and lookup and the UniProt accession-to-UniRef90 mapping.
# usage: download_metadata.sh WORK_DIR
# UNIPROT_URL selects the mirror; it always serves UniProt's *current* release.
set -euo pipefail
scripts="$(cd "$(dirname "$0")" && pwd)"
work=$1
afdb=${AFDB_URL:-https://steineggerlab.s3.amazonaws.com/afdbv6}
uniprot=${UNIPROT_URL:-https://ftp.expasy.org/databases/uniprot/current_release}

fetch() {
    [[ -s $2 ]] || "$scripts/prange_download.sh" "$1" "$2" 8
}

fetch "$afdb/afdb241.index" "$work/afdb241.index"
fetch "$afdb/afdb241.lookup" "$work/afdb241.lookup"
if [[ ! -s $work/idmapping_selected.tab.gz ]]; then
    fetch "$uniprot/knowledgebase/idmapping/idmapping_selected.tab.gz" "$work/idmapping_selected.tab.gz"
    # Record which release the mapping came from.
    curl -sS -L "$uniprot/relnotes.txt" -o "$work/uniprot_relnotes.txt" || true
fi
