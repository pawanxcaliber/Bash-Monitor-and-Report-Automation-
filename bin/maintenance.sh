#!/bin/bash
# Brief: Automated system maintenance and reporting script.
# Performs updates, log rotation, resource monitoring, and container checks.
# Generates a daily report file. Supports a dry-run mode.

set -euo pipefail 

source config/settings.conf 

REPORT_FILE=""
LOG_FILE="logs/maintenance_$(date +%Y%m%d_%H%M%S).log"

DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --dry-run)
    DRY_RUN=true
    echo "--- DRY RUN mode enabled ---"
    shift
    ;;
    *)
    echo "Warning: Unknown option or argument '$arg' ignored."
    shift
    ;;
  esac
done

mkdir -p logs

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting maintenance script at $(date)"
echo "-----------------------------------------"

update_packages() {
  echo "--- Running package updates ---"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would run package updates."
    echo "-------------------------------"
    return 0
  fi

  if [[ $EUID -ne 0 ]]; then
     echo "Attempting package updates with sudo..."
     if command -v apt &>/dev/null; then
       sudo apt update && sudo apt upgrade -y
     elif command -v yum &>/dev/null; then
       sudo yum update -y
     elif command -v dnf &>/dev/null; then
       sudo dnf update -y
     else
       echo "Error: Package manager (apt, yum, dnf) not found. Cannot perform updates."
       echo "-------------------------------"
       return 1
     fi
  else
    echo "Running package manager as root directly..."
    if command -v apt &>/dev/null; then
      apt update && apt upgrade -y
    elif command -v yum &>/dev/null; then
      yum update -y
    elif command -v dnf &>/dev/null; then
      dnf update -y
    else
      echo "Error: Package manager (apt, yum, dnf) not found. Cannot perform updates."
       echo "-------------------------------"
       return 1
    fi
  fi
  
  if [ $? -eq 0 ]; then
    echo "--- Package updates finished successfully ---"
  else
     echo "--- Package updates finished with errors ---"
  fi
  echo "-------------------------------"
  return 0
}

rotate_logs() {
  echo "--- Rotating logs ---"
  local state_file="./logrotate.state"
  local config_file="./logrotate.conf"
  
  if [ "$DRY_RUN" = true ]; then 
     echo "DRY RUN: Would rotate logs using $state_file and $config_file."
     echo "---------------------"
     return 0
  fi
  
  if [ ! -f "$config_file" ]; then
      echo "Error: Logrotate config file '$config_file' not found. Skipping log rotation."
      echo "---------------------"
      return 1
  fi
  
  touch "$state_file"
  
  logrotate --state "$state_file" "$config_file"
  
  if [ $? -eq 0 ]; then
    echo "Log rotation finished successfully."
  else
     echo "Log rotation finished with potential issues. Check output above."
  fi
  echo "---------------------"
}

check_cpu_ram() {
  echo "--- CPU & RAM Usage ---"
  cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/,//') 

  if [ -z "$cpu_idle" ] || ! [[ "$cpu_idle" =~ ^[0-9.]+$ ]]; then
     echo "CPU Usage: N/A (Error parsing top output format)"
  else
     cpu_usage=$(awk "BEGIN { printf \"%.2f\", 100 - $cpu_idle }")
     echo "CPU Usage: ${cpu_usage}%"
  fi

  mem_line=$(free -m | awk '/Mem:/')
   if [ -z "$mem_line" ]; then
     echo "Memory Usage: N/A (Error parsing free output)"
   else
     read -r _ total used free shared buff cache available <<< "$mem_line"
     if [ "$total" -gt 0 ]; then
        mem_usage_pct=$(awk "BEGIN { printf \"%.2f\", ($used/$total)*100 }")
        echo "Memory Usage: ${mem_usage_pct}%"
     else
        echo "Memory Usage: N/A (Total memory is zero)"
     fi
   fi
  echo "--------------------------"
}

check_disk() {
  echo "--- Disk Usage & Free Space ---"
  local disk_threshold="${DISK_THRESHOLD:-80}" 
  
  df -hP | awk 'NR==1 || ($0 ~ /^\/dev\// && !/snap/ && !/loop/ && !/tmpfs/)' 
  
  echo
  
  local root_info=$(df -hP / | awk 'NR>1 {print $4, $5}' | sed 's/%//')
  local root_avail=$(echo "$root_info" | awk '{print $1}')
  local root_usep=$(echo "$root_info" | awk '{print $2}')
  
  if [ -n "$root_usep" ] && [[ "$root_usep" =~ ^[0-9]+$ ]]; then
      echo "Root Partition (/) Usage: ${root_usep}%"
      echo "Root Partition (/) Available: ${root_avail}"
      
      if [ "$root_usep" -ge "$disk_threshold" ]; then
          echo "WARNING: Root partition usage (${root_usep}%) is at or above threshold (${disk_threshold}%)."
      fi
  else
     echo "Error: Could not determine root partition disk usage."
  fi
  
  echo "---------------------------"
}

top_procs() {
  echo "--- Top 2 Processes by CPU ---"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n3 || true
  
  echo;
  
  echo "--- Top 2 Processes by Memory ---"
  ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n3 || true
  echo "------------------------------"
}

check_docker() {
  echo "--- Docker Container Health ---"
  if ! command -v docker &>/dev/null; then
    echo "Docker CLI not found. Skipping Docker health checks."
    echo "------------------------------"
    return 0
  fi
  
  if ! docker info >/dev/null 2>&1; then
      echo "Docker daemon is not running or accessible. Skipping Docker health checks."
      echo "------------------------------"
      return 0
  fi
  
  local running_containers=$(docker ps -q)
  
  if [ -z "$running_containers" ]; then
      echo "No running Docker containers found."
  else
      echo "Checking running containers:"
      echo "CONTAINER NAME : HEALTH STATUS"
      echo "----------------------------------"
      for c in $running_containers; do
        local name=$(docker inspect --format '{{.Name}}' "$c")
        local health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo "Error getting health")
        echo "${name#:} : ${health}"
      done
  fi
  echo "------------------------------"
}

check_k8s() {
  echo "--- Kubernetes Pods (Non-Running) ---"
  if ! command -v kubectl &>/dev/null; then
    echo "kubectl CLI not found. Skipping K8s checks."
    echo "-------------------------"
    return 0
  fi

  if ! kubectl version --client=true >/dev/null 2>&1 && ! kubectl cluster-info >/dev/null 2>&1 --request-timeout=5s || true ; then
     echo "kubectl cannot connect to a cluster or config is invalid. Skipping K8s checks."
     echo "-------------------------"
     return 0
  fi

  echo "Checking for pods not in 'Running' phase across all namespaces:"
  kubectl get pods --all-namespaces --field-selector=status.phase!=Running --show-labels || true
  
  echo "-------------------------"
}

generate_report() {
  echo "--- Generating Report ---"
  REPORT_FILE="logs/daily-report-$(date +%Y-%m-%d).txt"
  mkdir -p logs
  
  echo "Generating report file: $REPORT_FILE"
  
  { 
    echo "Automated System Maintenance Report for $(hostname)"
    echo "Generated on: $(date)"
    echo "======================================="
    echo
    
    echo "=== Package Update Status ==="
    echo "Package updates were attempted prior to this report generation."
    echo "Check main script log for detailed results."
    echo "-----------------------------"
    echo
    
    echo "=== Log Rotation Status ==="
    echo "Log rotation was attempted prior to this report generation."
    echo "Check main script log for detailed results."
    echo "---------------------"
    echo
    
    echo "=== System Resource Usage ==="
    check_cpu_ram 
    echo;
    check_disk    
    echo
    
    echo "=== Top Processes ==="
    top_procs 
    echo
    
    echo "=== Container Health Checks ==="
    check_docker 
    echo;
    check_k8s    
    echo
    
    echo "======================================="
    echo "Report End."
    
  } > "$REPORT_FILE"

  if [ -s "$REPORT_FILE" ]; then
      echo "Report generated successfully: $REPORT_FILE"
      echo "$REPORT_FILE"
      return 0
  else
      echo "Error: Report file '$REPORT_FILE' was not generated or is empty."
      REPORT_FILE=""
      return 1
  fi
  echo "-------------------------"
}

echo "Running core maintenance tasks and report generation..."

update_packages
rotate_logs

GENERATED_REPORT_PATH=$(generate_report)

echo "-----------------------------------------"
echo "Maintenance script finished at $(date)"