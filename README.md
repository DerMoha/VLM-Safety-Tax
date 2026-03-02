# vlm-safety-tax

SLURM evaluation scripts for the bachelor's thesis "The Safety Tax in Vision-Language Models". The study benchmarks 14 open-source VLM checkpoints to investigate whether safety-aligned post-training degrades reasoning capability.

---

## Repository layout

```
vlm-safety-tax/
├── scripts/                    # 14 SLURM batch jobs, one per model
├── helm_patches/               # modified HELM source files (see below)
│   ├── benchmark/metrics/output_processors.py
│   └── benchmark/run_specs/vlm_run_specs.py
├── prod_env/
│   ├── model_deployments.yaml  # HELM client config (points to localhost:9001)
│   ├── model_metadata.yaml
│   └── tokenizer_configs.yaml
├── run_entries_vhelm.conf      # benchmark run entries
├── schema_vhelm.yaml           # VHELM schema
├── submit_all_sequential.sh    # submits all 14 jobs via dependency chaining
├── extract_benchmark_data.py   # parses HELM stats.json output into CSV
├── benchmark_summary_consolidated-qwen2v2.csv      # aggregated results per model
└── complete_benchmark_data_consolidated-qwen2v2.csv # per-benchmark raw scores
```

---

## Setup

Two separate Python 3.12 venvs are required -- vLLM and HELM have conflicting `transformers` version requirements. Place both as siblings next to this repo.

```bash
# vLLM venv (serving)
python3.12 -m venv vllm_venv
source vllm_venv/bin/activate
pip install vllm==0.10.2 torch==2.8.0 transformers==4.56.1
deactivate

# HELM venv (evaluation)
python3.12 -m venv vhelm_venv
source vhelm_venv/bin/activate
pip install "crfm-helm[vlm]==0.5.9" torch==2.8.0 transformers==4.52.4
deactivate
```

Then apply the HELM patches (see below).

---

## HELM patches

Two files in `helm_patches/` need to be copied into the HELM installation to support R1-style reasoning models:

- `output_processors.py` -- adds `remove_r1_thinking_and_answer_tags`, registered as `output_processor` in `prod_env/model_deployments.yaml` for the four R1-style models
- `vlm_run_specs.py` -- raises `max_tokens` to 4096 and clears `stop_sequences` for benchmarks where R1 models need full reasoning traces

Models without `<think>` output (all base, safety-aligned, and GRPO models) are unaffected.

---

## Running

Update the paths at the top of each script in `scripts/` to match your cluster:

```bash
DATA_DIR="/your/path"
VLLM_VENV="${DATA_DIR}/vllm_venv"
VHELM_VENV="${DATA_DIR}/vhelm_venv"
LOG_DIR="${DATA_DIR}/logs"
```

Then submit all 14 jobs sequentially -- only one GPU is needed since jobs run one at a time:

```bash
bash submit_all_sequential.sh
```

Each job starts a vLLM server, waits for it to be ready, runs `helm-run` against it, then shuts it down. Jobs are chained via `--dependency=afterok`.

---

## Extracting results

Pre-computed result CSVs are included in this repository for convenience:

| File | Description |
|------|-------------|
| `benchmark_summary_consolidated-qwen2v2.csv` | Aggregated scores per model across all benchmarks |
| `complete_benchmark_data_consolidated-qwen2v2.csv` | Per-benchmark, per-instance raw scores |

To regenerate them from raw HELM output:

```bash
source vhelm_venv/bin/activate
python extract_benchmark_data.py
```

This parses `benchmark_output/runs/qwen2vl-v2/` and writes both CSV files.

---

## Reproducibility

All models are pinned to exact HuggingFace commit SHAs via `--revision` in each script. Full hashes and software versions are documented in the thesis appendix.
