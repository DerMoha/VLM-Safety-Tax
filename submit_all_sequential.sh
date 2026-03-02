#!/usr/bin/env bash
# submit_all_sequential.sh
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="/nfs/data8/hamid/VHELM/scripts/generated_scripts_full"
LOG_FILE="job_submission_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

mapfile -t SCRIPTS < <(printf '%s\n' "$SCRIPT_DIR"/*.sh | LC_ALL=C sort -V)

this_file="$(realpath "${BASH_SOURCE[0]}")"
tmp=()
for s in "${SCRIPTS[@]}"; do
  [[ "$(realpath "$s")" == "$this_file" ]] && continue
  tmp+=("$s")
done
SCRIPTS=("${tmp[@]}")

if ((${#SCRIPTS[@]} == 0)); then
  log "ERROR: Keine .sh-Dateien in $SCRIPT_DIR gefunden."
  exit 1
fi

DEP_KIND="${DEP_KIND:-afterok}"

submit() {
  local _job
  if ! _job=$(sbatch --parsable "$@"); then
    log "ERROR: sbatch fehlgeschlagen für: $*"
    exit 1
  fi
  _job="${_job%%;*}"
  [[ "$_job" =~ ^[0-9]+$ ]] || { 
    log "ERROR: Unerwartete Job-ID: $_job"
    exit 1
  }
  printf '%s' "$_job"
}

log "=========================================="
log "Starting sequential job submission"
log "Script directory: $SCRIPT_DIR"
log "Found ${#SCRIPTS[@]} scripts to submit"
log "Dependency type: $DEP_KIND"
log "=========================================="

# Summary BEFORE submission
log ""
log "Job Chain to be submitted:"
log "=========================="
for i in "${!SCRIPTS[@]}"; do
  log "  $((i+1)). $(basename "${SCRIPTS[$i]}")"
done
log ""

# First job
job_id=$(submit "${SCRIPTS[0]}")
log "Submitted $(basename "${SCRIPTS[0]}") -> Job ID: $job_id"

# Rest with dependency
for script in "${SCRIPTS[@]:1}"; do
  job_id=$(submit --dependency="${DEP_KIND}:${job_id}" "$script")
  log "Submitted $(basename "$script") -> Job ID: $job_id (depends on previous)"
done

log "=========================================="
log "All ${#SCRIPTS[@]} jobs submitted successfully!"
log "Last Job ID: $job_id"
log "Monitor with: squeue -u $USER"
log "Log file: $LOG_FILE"
log "=========================================="