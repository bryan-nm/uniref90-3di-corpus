#!/usr/bin/env bash
# Run stream_pairs.py on every selection shard in parallel, with a memory watchdog.
# usage: run_stream.sh SELECTION_SHARD_DIR OUT_DIR
# Finished shards get a .done marker and are skipped on rerun. Logs: OUT_DIR/s*.log and
# OUT_DIR/mem.log. MEM_LIMIT_GB (default 4) is the total RSS at which the run is killed.
set -uo pipefail
scripts="$(cd "$(dirname "$0")" && pwd)"
sel_dir=$1; out=$2
limit_kb=$((${MEM_LIMIT_GB:-4} * 1024 * 1024))
mkdir -p "$out"

pipeline_rss_kb() {
    ps -ax -o rss=,command= | awk '/stream_pairs\.py|curl .*afdb241/ && !/awk/ {s += $1} END {print s + 0}'
}

for sel in "$sel_dir"/sel_*.tsv; do
    s=$(basename "$sel" .tsv); s=${s#sel_}
    [[ -e $out/s$s.done ]] && continue
    ( python3 "$scripts/stream_pairs.py" "$sel" "$out/s$s" 2> "$out/s$s.log" && touch "$out/s$s.done" ) &
done

while [[ -n $(jobs -r -p) ]]; do
    rss=$(pipeline_rss_kb)
    echo "$(date '+%F %T') rss_mb=$((rss / 1024)) running=$(jobs -r -p | wc -l | tr -d ' ')" >> "$out/mem.log"
    if ((rss > limit_kb)); then
        echo "RSS over limit, killing pipeline" | tee -a "$out/mem.log" >&2
        pkill -f 'stream_pairs\.py'
        exit 1
    fi
    sleep 15
done
wait

total=$(ls "$sel_dir"/sel_*.tsv | wc -l | tr -d ' ')
done_n=$(ls "$out"/s*.done 2> /dev/null | wc -l | tr -d ' ')
echo "$done_n of $total shards done"
[[ $done_n -eq $total ]]
