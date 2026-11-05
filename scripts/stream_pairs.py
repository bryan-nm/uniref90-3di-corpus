#!/usr/bin/env python3
"""Stream selected records out of the AFDB v6 MMseqs2 databases (AA + 3Di).

The AA (`afdb241`) and 3Di (`afdb241_ss`) data files share one index, so both
are read in lockstep over the same byte range with HTTP range requests. Only the
records listed in the selection table are written; everything else is skipped
in-stream, so nothing but the output FASTA files touches the disk.

Selection TSV columns (no header, sorted by offset):
    key  offset  length  fasta_header

The selection is read line by line, never loaded whole, so memory use stays flat.
For parallel runs, split the selection first with split_selection.sh and give each
process its own shard file.
"""
import argparse
import os
import subprocess
import sys
import time

BASE_URL = "https://steineggerlab.s3.amazonaws.com/afdbv6"
CHUNK = 1 << 20


class RangeReader:
    """Sequential reader over [start, end) of a remote file; reconnects on drops."""

    def __init__(self, url, start, end, retries=20):
        self.url, self.pos, self.end, self.retries = url, start, end, retries
        self.proc = None
        self._open()

    def _open(self):
        if self.proc:
            self.proc.kill()
            self.proc.wait()
        self.proc = subprocess.Popen(
            ["curl", "-sS", "--fail", "-L", "-r", f"{self.pos}-{self.end - 1}", self.url],
            stdout=subprocess.PIPE, bufsize=CHUNK,
        )

    def read(self, n):
        parts = []
        while n > 0:
            buf = self.proc.stdout.read(min(n, CHUNK))
            if not buf:
                if self.pos >= self.end or self.retries == 0:
                    raise IOError(f"{self.url}: stream ended at {self.pos}, wanted to {self.end}")
                self.retries -= 1
                print(f"[warn] {self.url}: reconnecting at {self.pos}", file=sys.stderr)
                time.sleep(5)
                self._open()
                continue
            parts.append(buf)
            self.pos += len(buf)
            n -= len(buf)
        return b"".join(parts)

    def skip(self, n):
        while n > 0:
            n -= len(self.read(min(n, CHUNK)))

    def close(self):
        self.proc.kill()
        self.proc.wait()


def parse(line):
    key, off, length, header = line.rstrip("\n").split("\t", 3)
    return int(off), int(length), header


def iter_rows(path):
    with open(path) as fh:
        for line in fh:
            yield parse(line)


def byte_span(path):
    """First record's offset and last record's end, reading only the file's head and tail."""
    with open(path, "rb") as fh:
        first = fh.readline().decode()
        if not first:
            return None
        fh.seek(max(0, os.path.getsize(path) - 65536))
        last = fh.read().decode().rstrip("\n").rsplit("\n", 1)[-1]
    off, length, _ = parse(last)
    return parse(first)[0], off + length


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("selection")
    ap.add_argument("out_prefix", help="writes <prefix>.aa.fasta and <prefix>.3di.fasta")
    ap.add_argument("--base-url", default=BASE_URL)
    ap.add_argument("--aa-db", default="afdb241")
    ap.add_argument("--ss-db", default="afdb241_ss")
    args = ap.parse_args()
    name = os.path.basename(args.out_prefix)

    span = byte_span(args.selection)
    if span is None:
        return
    start, end = span
    aa = RangeReader(f"{args.base_url}/{args.aa_db}", start, end)
    ss = RangeReader(f"{args.base_url}/{args.ss_db}", start, end)

    pos, n, bad, t0 = start, 0, 0, time.time()
    with open(f"{args.out_prefix}.aa.fasta", "w") as fa, open(f"{args.out_prefix}.3di.fasta", "w") as f3:
        for off, length, header in iter_rows(args.selection):
            aa.skip(off - pos)
            ss.skip(off - pos)
            a = aa.read(length).rstrip(b"\n\x00").decode()
            s = ss.read(length).rstrip(b"\n\x00").decode()
            pos = off + length
            if len(a) != len(s) or "\n" in a:
                bad += 1
                print(f"[warn] skipping {header}: aa/3di length {len(a)}/{len(s)}", file=sys.stderr)
                continue
            fa.write(f">{header}\n{a}\n")
            f3.write(f">{header}\n{s.upper()}\n")
            n += 1
            if n % 1_000_000 == 0:
                mb = (pos - start) / 1e6
                print(f"[{name}] {n:,} records, {mb:,.0f} MB, {mb / (time.time() - t0):.1f} MB/s",
                      file=sys.stderr, flush=True)
    aa.close()
    ss.close()
    print(f"[{name}] done: {n:,} written, {bad:,} skipped, {time.time() - t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
