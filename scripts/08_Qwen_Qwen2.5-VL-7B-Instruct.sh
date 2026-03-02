#!/usr/bin/env bash
#
#SBATCH --job-name Qwen_Qwen2.5-VL-7B-Instruct
#SBATCH --output=/nfs/data8/hamid/VHELM/logs/slurm_Qwen_Qwen2.5-VL-7B-Instruct_%j.txt
#SBATCH --ntasks=1
#SBATCH --time=24:00:00
#SBATCH --gres=gpu:1
#SBATCH --partition=major

set -euo pipefail

# =========================
# JOB INFO
# =========================
echo "========================================="
echo "Model: Qwen/Qwen2.5-VL-7B-Instruct"
echo "Host: $(hostname)"
echo "Start: $(date)"
echo "SLURM Job ID: ${SLURM_JOB_ID}"
echo "========================================="

nvidia-smi || true

# =========================
# PATHS
# =========================
DATA_DIR="/nfs/data8/hamid/VHELM"
VLLM_VENV="/nfs/data8/hamid/VHELM/vllm_venv"
VHELM_VENV="/nfs/data8/hamid/VHELM/vhelm_venv"
LOG_DIR="/nfs/data8/hamid/VHELM/logs"
PORT=9001

cd "${DATA_DIR}"
echo "Working directory: $(pwd)"

# =========================
# CLEANUP FUNCTION
# =========================
VLLM_PID=""

cleanup() {
  echo ""
  echo "Cleanup triggered..."
  if [[ -n "${VLLM_PID}" ]] && kill -0 "${VLLM_PID}" 2>/dev/null; then
    echo "Stopping vLLM server (PID: ${VLLM_PID})..."
    kill "${VLLM_PID}" 2>/dev/null || true
    wait "${VLLM_PID}" 2>/dev/null || true
  fi
  
  # Extra: Kill any lingering processes on this port
  if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Killing lingering processes on port ${PORT}..."
    lsof -ti:${PORT} | xargs kill -9 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

# =========================
# WAIT FOR PORT TO BE FREE
# =========================
echo "Checking if port ${PORT} is free..."
for i in {1..60}; do
  if ! lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port ${PORT} is free"
    break
  fi
  if [[ ${i} -eq 1 ]]; then
    echo "Port ${PORT} is in use, waiting..."
  fi
  if [[ ${i} -eq 60 ]]; then
    echo "ERROR: Port ${PORT} still in use after 60 seconds"
    exit 1
  fi
  sleep 1
done

# =========================
# START VLLM SERVER
# =========================
echo "Activating vLLM virtual environment"
source "${VLLM_VENV}/bin/activate"
echo "vLLM environment activated"

export VLLM_USE_V1=0

unset VLLM_ATTENTION_BACKEND   # falls gesetzt und Probleme macht

# Set VHELM-specific environment variables
export RUN_ENTRIES_CONF_PATH=run_entries_vhelm.conf
export SCHEMA_PATH=schema_vhelm.yaml
export VLLM_LOGGING_LEVEL=DEBUG
export PYTHONPATH="${DATA_DIR}:${PYTHONPATH:-}"

vllm_log="${LOG_DIR}/vllm_Qwen_Qwen2.5-VL-7B-Instruct_${SLURM_JOB_ID}.log"

echo "Launching vLLM server for Qwen/Qwen2.5-VL-7B-Instruct"
echo "Log file: ${vllm_log}"

python -m vllm.entrypoints.openai.api_server \
  --model "Qwen/Qwen2.5-VL-7B-Instruct" \
  --revision "cc594898137f460bfe9f0759e9844b3ce807cfb5" \
  --seed 42 \
  --served-model-name "Qwen/Qwen2.5-VL-7B-Instruct" "Qwen2.5-VL-7B-Instruct" \
  --host 0.0.0.0 \
  --trust-remote-code \
  --limit-mm-per-prompt '{"image": 7}' \
  --max-model-len 10240 \
  --enforce-eager \
  --port ${PORT} > "${vllm_log}" 2>&1 &

VLLM_PID=$!

# Check if process started
sleep 2
if ! kill -0 "${VLLM_PID}" 2>/dev/null; then
  echo "ERROR: vLLM server died immediately!"
  echo "Check log: ${vllm_log}"
  exit 1
fi

echo "vLLM server started with PID: ${VLLM_PID}"

# =========================
# WAIT FOR SERVER
# =========================
echo "Waiting for vLLM server to start (initial sleep: 100s)..."
sleep 100

MAX_ATTEMPTS=40
for i in $(seq 1 ${MAX_ATTEMPTS}); do
  # Check if process still alive
  if ! kill -0 "${VLLM_PID}" 2>/dev/null; then
    echo "ERROR: vLLM server died during startup!"
    echo "Check log: ${vllm_log}"
    exit 1
  fi
  
  # Check if server responding
  if curl -s "http://localhost:${PORT}/v1/models" 2>/dev/null | grep -q "Qwen/Qwen2.5-VL-7B-Instruct"; then
    echo "vLLM server is ready and serving Qwen/Qwen2.5-VL-7B-Instruct!"
    break
  fi
  
  if [[ ${i} -eq ${MAX_ATTEMPTS} ]]; then
    echo "ERROR: Server failed to start after ${MAX_ATTEMPTS} attempts"
    echo "Check log: ${vllm_log}"
    exit 1
  fi
  
  echo "Attempt ${i}/${MAX_ATTEMPTS}: Server not ready yet..."
  sleep 15
done

# =========================
# RUN HELM EVALUATION
# =========================
echo ""
echo "========================================="
echo "Starting HELM evaluation"
echo "Mode: full"
echo "========================================="

echo "Switching to VHELM virtual environment"
deactivate
source "${VHELM_VENV}/bin/activate"
echo "VHELM environment activated"

helm-run --run-entries \
  "vqa:model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Accounting,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Economics,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Finance,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Computer_Science,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Math,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Physics,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=Psychology,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mmmu:subject=History,question_type=multiple-choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mm_star:category=instance_reasoning,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mm_star:category=logical_reasoning,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "mm_star:category=math,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "math_vista:grade=daily_life,question_type=multi_choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "math_vista:grade=elementary_school,question_type=multi_choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "math_vista:grade=high_school,question_type=multi_choice,model=Qwen/Qwen2.5-VL-7B-Instruct" \
  "hateful_memes:model=Qwen/Qwen2.5-VL-7B-Instruct" \
  --models-to-run "Qwen/Qwen2.5-VL-7B-Instruct" \
  --suite qwen2vl-v2 \
  --max-eval-instances 1000

EXIT_CODE=$?

if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "Evaluation completed successfully for Qwen/Qwen2.5-VL-7B-Instruct"
else
  echo "Evaluation failed for Qwen/Qwen2.5-VL-7B-Instruct with exit code ${EXIT_CODE}"
fi

# =========================
# DONE
# =========================
echo "Stopping vLLM server..."
kill "${VLLM_PID}" 2>/dev/null || true

echo ""
echo "========================================="
echo "Job finished at: $(date)"
echo "Exit code: ${EXIT_CODE}"
echo "========================================="

exit ${EXIT_CODE}
