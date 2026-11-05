#!/usr/bin/env python3
"""Pick one AFDB v6 entry per UniRef90 cluster.

Joins afdb241.index + afdb241.lookup (key -> offset/length/accession) with
UniProt's idmapping_selected.tab.gz (accession -> UniRef90 cluster). Within each
cluster the representative accession is used if it has a model, otherwise the
longest member that does. No quality filtering.

Writes a selection TSV for stream_pairs.py, sorted by offset:
    key  offset  length  "AF-<acc>-F1 UniRef90_<id>"
"""
import argparse
import sys

import numpy as np
import pandas as pd

CHUNK = 5_000_000


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_afdb(index_path, lookup_path, limit):
    keys, offs, lens, accs = [], [], [], []
    idx = pd.read_csv(index_path, sep="\t", header=None, names=["key", "off", "len"],
                      dtype="int64", chunksize=CHUNK, nrows=limit)
    lku = pd.read_csv(lookup_path, sep="\t", header=None, names=["key", "name", "file"],
                      usecols=[0, 1], dtype={"key": "int64", "name": str}, chunksize=CHUNK, nrows=limit)
    for i, (a, b) in enumerate(zip(idx, lku)):
        if not np.array_equal(a["key"].to_numpy(), b["key"].to_numpy()):
            sys.exit("index and lookup are not in the same key order")
        # AF-<acc>-F1-model_v6; isoform entries keep their suffix (P12345-2) and so never
        # match idmapping, which lists canonical accessions only.
        acc = b["name"].str.removeprefix("AF-").str.removesuffix("-F1-model_v6")
        if acc.str.contains("model").any():
            sys.exit(f"chunk {i}: unexpected AFDB entry name (not -F1-model_v6)")
        keys.append(a["key"].to_numpy())
        offs.append(a["off"].to_numpy())
        lens.append(a["len"].to_numpy(dtype="int32"))
        accs.append(acc.to_numpy(dtype="S13"))
        log(f"afdb rows: {sum(map(len, keys)):,}")
    return np.concatenate(keys), np.concatenate(offs), np.concatenate(lens), np.concatenate(accs)


def map_uniref90(idmapping_path, accs_sorted):
    ur90 = np.zeros(len(accs_sorted), dtype="S13")
    clusters = []
    n = 0
    for chunk in pd.read_csv(idmapping_path, sep="\t", header=None, usecols=[0, 8], names=["acc", "ur90"],
                             dtype=str, chunksize=CHUNK):
        chunk = chunk.dropna()
        acc = chunk["acc"].to_numpy(dtype="S13")
        cl = chunk["ur90"].str.removeprefix("UniRef90_").to_numpy(dtype="S13")
        pos = np.searchsorted(accs_sorted, acc).clip(max=len(accs_sorted) - 1)
        hit = accs_sorted[pos] == acc
        ur90[pos[hit]] = cl[hit]
        clusters.append(np.unique(cl))
        n += len(chunk)
        log(f"idmapping rows: {n:,}")
    log(f"UniRef90 clusters with a UniProtKB member: {len(np.unique(np.concatenate(clusters))):,}")
    return ur90


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("index")
    ap.add_argument("lookup")
    ap.add_argument("idmapping")
    ap.add_argument("out")
    ap.add_argument("--limit", type=int, help="only use the first N AFDB entries (testing)")
    args = ap.parse_args()

    keys, offs, lens, accs = load_afdb(args.index, args.lookup, args.limit)
    order = np.argsort(accs, kind="stable")
    keys, offs, lens, accs = keys[order], offs[order], lens[order], accs[order]
    ur90 = map_uniref90(args.idmapping, accs)

    mapped = ur90 != b""
    log(f"AFDB entries: {len(accs):,}; with UniRef90 cluster: {mapped.sum():,}; unmapped: {(~mapped).sum():,}")
    keys, offs, lens, accs, ur90 = keys[mapped], offs[mapped], lens[mapped], accs[mapped], ur90[mapped]

    is_rep = ur90 == accs
    order = np.lexsort((-lens, ~is_rep, ur90))
    first = np.ones(len(order), dtype=bool)
    first[1:] = ur90[order][1:] != ur90[order][:-1]
    pick = order[first]
    log(f"UniRef90 clusters with an AFDB model: {len(pick):,} (representative used: {is_rep[pick].sum():,})")

    pick = pick[np.argsort(offs[pick])]
    with open(args.out, "w") as fh:
        for k, o, l, a, u in zip(keys[pick], offs[pick], lens[pick], accs[pick], ur90[pick]):
            fh.write(f"{k}\t{o}\t{l}\tAF-{a.decode()}-F1 UniRef90_{u.decode()}\n")


if __name__ == "__main__":
    main()
