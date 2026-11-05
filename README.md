# UniRef90 AA/3Di corpus

Builds a paired amino-acid and 3Di FASTA corpus, for use as a search database when building
paired sequence-structure alignments. It holds one AlphaFold DB v6 entry per UniRef90 cluster,
plus any structures you tokenize yourself and append.

The AlphaFold DB files are streamed and filtered on the fly, so the 457 GiB Foldseek AFDB tarball
is never downloaded. There are no quality filters and no train/test splits.

## Output

`PREFIX.aa.fasta` and `PREFIX.3di.fasta` have the same headers in the same order, one sequence per
line, with uppercase 3Di:

```
>AF-P69905-F1 UniRef90_P69905
>ESM-P04517-2036-2269 ProtClu90_ESM-P04517-2036-2269 members=12
```

## Requirements

- bash, curl and awk; Python 3 with `pip install -r requirements.txt`
- [Foldseek](https://github.com/steineggerlab/foldseek) and
  [MMseqs2](https://github.com/soedinglab/MMseqs2), only for tokenizing your own structures
- About 18 GB of RAM for the selection step (measured peak 17.4 GB); the streaming step uses about
  500 MB
- About 140 GB of free disk at peak, including 54 GB for the corpus. The shards can be deleted
  after assembly.

Developed on macOS (bash 3.2, Apple `sort`); not tested elsewhere.

## Usage

Build the AFDB corpus:

```bash
./build_corpus.sh --work work --out work/corpus
```

Tokenize structures, then include them in the build:

```bash
scripts/prepare_structures.sh my_structures/ work/mine
./build_corpus.sh --work work --out work/corpus --append work/mine
```

Append tokenized sequences to a corpus you already have, without streaming anything:

```bash
./build_corpus.sh --out work/corpus_v2 --base work/corpus --append work/mine
```

`--append` is repeatable, and takes any prefix with matching `.aa.fasta` and `.3di.fasta` files.
Those files are concatenated as they are, so they must already use the corpus format. Every build
ends with `scripts/validate_pairs.sh`, which fails on mismatched pairs, invalid 3Di letters or
duplicate IDs. Finished steps and shards are skipped on rerun.

`prepare_structures.sh` keeps one representative per cluster at 90% identity and 80% coverage by
default. Use `--no-cluster` to keep every structure, and see the top of the script for its other
options.

## How the stream works

The Steinegger lab publishes AFDB v6 as an
[MMseqs2 database](https://opendata.mmseqs.org/afdbv6/). The AA (`afdb241`) and 3Di (`afdb241_ss`)
data files are uncompressed, about 80 GB each, and have the same record layout, so one index
locates records in both.

| Step | Script | What it does |
|---|---|---|
| 1 | `download_metadata.sh` | Fetches `afdb241.index`, `afdb241.lookup` and UniProt's `idmapping_selected.tab.gz` |
| 2 | `build_selection.py` | Maps AFDB accessions to UniRef90 clusters and picks one entry per cluster: the cluster's representative if it has a model, otherwise its longest member with one |
| 3 | `split_selection.sh` | Splits the selection into shard files of equal byte span |
| 4 | `run_stream.sh`, `stream_pairs.py` | Reads both data files over HTTP range requests in parallel and keeps only the selected records; only the output reaches the disk |
| 5 | `assemble_corpus.sh` | Concatenates the shards and any `--append` inputs |
| 6 | `validate_pairs.sh` | Checks the result |

Selected records are spread throughout the files, so step 4 still transfers the full 160 GB. It
reads each selection shard line by line to keep memory flat, and `run_stream.sh` kills the run if
the pipeline exceeds 4 GB (`MEM_LIMIT_GB`).

## This build

Built November 2026 with Foldseek 10.941cd33 and MMseqs2 771ee23.

| | |
|---|---|
| AFDB | v6, built from UniProt 2025_03; 241,070,489 entries |
| UniRef90 | Release 2026_04; 125,724,408 clusters |
| Corpus | 71,438,479 pairs: 71,437,805 AFDB, 674 ESMFold proteases |
| Mean length | 337.8 residues |
| Size | 26.8 GB per file |
| Stream | 16 shards, about 4.2 hours, peak 495 MB |

```
a864db5f666665c63b5b2eccbc9fc762ee5d1cce9c8271ff7d54145a07420b85  uniref90_afdb_proteases.aa.fasta
9a6287fbb0a35082f57d2b8998a80b679cd47cd995a24c4c32bd8b98d2a699b1  uniref90_afdb_proteases.3di.fasta
```

### Coverage

UniProt removed many unreviewed entries after 2025_03, taking UniProtKB from 253.6M to 154.2M entries
and UniRef90 from 208.0M to 125.7M clusters. Of the 241.1M AFDB entries, 106.5M still map to a
UniRef90 cluster by accession; the other 134.6M are dropped. Isoform entries (`AF-P12345-2-F1`) are
also dropped, because the mapping file lists canonical accessions only.

| UniRef90 2026_04 clusters | |
|---|---|
| Total | 125,724,408 |
| With a UniProtKB member | 96,792,496 |
| With an AFDB v6 model (in this corpus) | 71,437,805 |

Clusters without a UniProtKB member cannot be matched by accession. The reasons the remaining 25.4M
clusters have no model were not investigated; likely causes are proteins newer than 2025_03 and
proteins over AFDB's length limit.

### Regenerating it

`download_metadata.sh` fetches UniProt's *current* release, so a later run uses a newer mapping and
gives a different corpus. Releases from the matching period are only archived as whole tarballs
(186 GB for the 2025_03 knowledgebase), with no separate mapping file. Keep your
`idmapping_selected.tab.gz` if you need to rebuild the same selection.

## Case study: TEV-like proteases

TEV-like proteases are largely missing from AFDB, because they are encoded in polyproteins too long
for AFDB to include. Of the 15,210 parent accessions in our set, 6 have an AFDB v6 model. UniProt also
treats the polyprotein as a single entry: the 5,475 parents still in UniProtKB fall into 809 UniRef90
clusters of whole polyproteins, and the protease domains have no entries of their own.

So the domains could not be matched to UniRef90, and were clustered and appended instead. The input
was 15,214 ESMFold-predicted domain structures, kept outside this repo, named like
`000000_sp_P04517_POLG_TEV_2036-2269.pdb.gz`.

```bash
scripts/prepare_structures.sh \
    --id-prefix ESM --cluster-prefix ProtClu90 --names uniprot-domain --threads 12 \
    proteases_monomeric_20261006_220214/structures work/protease_reps90

./build_corpus.sh --work work --append work/protease_reps90
```

- Foldseek tokenized all 15,214 structures. Its AA sequences match the residues in the PDB files.
- MMseqs2 clustered them to 674 clusters at 90% identity and 80% coverage. 364 are singletons, and
  the largest has 3,348 members.
- A Swiss-Prot member is the representative where a cluster has one, following UniRef, so TEV appears
  as P04517 (a cluster of 12) rather than another isolate.
- All 674 were appended. There was no pLDDT filter, and no check for homologs already in the AFDB
  part of the corpus.

## What has been verified

The corpus was built with earlier versions of these scripts. This repo's code was then checked
against it:

- `build_selection.py`, run on the full inputs, reproduces the selection table byte for byte
  (13 minutes).
- `prepare_structures.sh` reproduces the same 674 protease records. Only their order differs, because
  it follows MMseqs2's cluster output.
- `build_corpus.sh` on the first 200,000 selected entries, streamed with 4 shards, matches the
  start of the corpus byte for byte, and `--append` and `--base` both run.
- The full 4-hour stream has not been rerun from this repo.
