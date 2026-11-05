#!/usr/bin/env python3
"""Write paired AA/3Di FASTA for one representative of each cluster, with corpus-style headers:
    ><id_prefix>-<name> <cluster_prefix>_<id_prefix>-<name> members=<n>

CLUSTER_TSV has "rep <tab> member" rows (MMseqs2 easy-cluster's _cluster.tsv); FASTA names are
structure file stems.

--names stem keeps the stem as <name> and MMseqs2's representative. --names uniprot-domain expects
stems such as 000000_sp_P04517_POLG_TEV_2036-2269, gives <name> = P04517-2036-2269, and, like
UniRef, prefers a Swiss-Prot member as the representative.
"""
import argparse
import collections


def read_fasta(path):
    seqs, name = {}, None
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith(">"):
                name = line[1:].split()[0].removesuffix(".gz").removesuffix(".pdb").removesuffix(".cif")
                seqs[name] = []
            else:
                seqs[name].append(line)
    return {k: "".join(v) for k, v in seqs.items()}


def strip_name(name):
    return name.removesuffix(".gz").removesuffix(".pdb").removesuffix(".cif")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cluster_tsv")
    ap.add_argument("aa_fasta")
    ap.add_argument("ss_fasta")
    ap.add_argument("out_prefix")
    ap.add_argument("--id-prefix", default="EXT")
    ap.add_argument("--cluster-prefix", default="Clu90")
    ap.add_argument("--names", choices=["stem", "uniprot-domain"], default="stem")
    args = ap.parse_args()

    clusters = collections.defaultdict(list)
    with open(args.cluster_tsv) as fh:
        for line in fh:
            rep, member = line.rstrip("\n").split("\t")
            clusters[strip_name(rep)].append(strip_name(member))
    aa, ss = read_fasta(args.aa_fasta), read_fasta(args.ss_fasta)

    with open(f"{args.out_prefix}.aa.fasta", "w") as fa, open(f"{args.out_prefix}.3di.fasta", "w") as f3:
        for rep, mems in clusters.items():
            name = rep
            if args.names == "uniprot-domain":
                rep = next((m for m in mems if m.split("_")[1] == "sp"), rep)
                parts = rep.split("_")
                name = f"{parts[2]}-{parts[-1]}"
            cid = f"{args.id_prefix}-{name}"
            header = f"{cid} {args.cluster_prefix}_{cid} members={len(mems)}"
            fa.write(f">{header}\n{aa[rep]}\n")
            f3.write(f">{header}\n{ss[rep].upper()}\n")
    print(f"wrote {len(clusters)} representatives covering {sum(map(len, clusters.values()))} structures")


if __name__ == "__main__":
    main()
