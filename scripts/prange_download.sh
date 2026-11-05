#!/usr/bin/env bash
# Download a URL with N parallel byte-range requests, then join the parts.
# usage: prange_download.sh URL OUTFILE [N]
set -euo pipefail
url=$1; out=$2; n=${3:-8}
len=$(curl -sIL "$url" | awk -F': ' 'tolower($1)=="content-length"{v=$2+0} END{print v}')
parts="$out.parts"; mkdir -p "$parts"
for ((i = 0; i < n; i++)); do
    s=$((len * i / n)); e=$((len * (i + 1) / n - 1))
    curl -sS -L --retry 10 -r "$s-$e" -o "$parts/p$i" "$url" &
done
wait
for ((i = 0; i < n; i++)); do cat "$parts/p$i"; done > "$out"
[[ $(wc -c < "$out") -eq $len ]] || { echo "size mismatch for $out" >&2; exit 1; }
rm -rf "$parts"
echo "done $out ($len bytes)"
