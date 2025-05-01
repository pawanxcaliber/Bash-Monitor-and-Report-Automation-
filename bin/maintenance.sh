#!/bin/bash
# Automated System Maintenance & Reporting Script

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Exit immediately if a command in a pipeline fails.
set -euo pipefail 

# --- Configuration Loading ---
# Load settings from config file.
# Source this after basic arguments like --dry-run are parsed.
# We'll add argument parsing below.
source config/settings.conf 

# --- Variables ---
# Variable to hold the path of the generated report file
REPORT_FILE=""
# Variable to hold the path for the main script's execution log
# This will capture stdout and stderr from the script's execution
LOG_FILE="logs/maintenance_$(date +%Y%m%d_%H%M%S).log"

# --- Argument Parsing ---
# Initialize variables for arguments
DRY_RUN=false

# Parse command line arguments
for arg in "$@"; do
  case $arg in
    --dry-run)
    DRY_RUN=true
    echo "--- DRY RUN mode enabled ---"
    shift # Remove argument
    ;;
    *)
    # Unknown option or other arguments not handled yet
    echo "Warning: Unknown option or argument '$arg' ignored."
    # Depending on requirements, you might want to exit here for strictness.
    # exit 1 
    shift # Remove argument
    ;;
  esl
done

# --- Logging Setup ---
# Ensure the logs directory exists
mkdir -p logs

# Redirect stdout and stderr of the entire script to the LOG_FILE.
# 'tee -a' sends output to both the file and the console (if not run by cron yet).
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting maintenance script at $(date)"
echo "-----------------------------------------"

# --- Define Functions Below ---

# 3.1 Package Updates
update_packages() {
  echo "--- Running package updates ---"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would run package updates."
    echo "-------------------------------"
    return 0 # In dry run, assume success for workflow
  fi

  # Check if running as root (updates require sudo). Sudo is needed if script is run by user cron.
  if [[ $EUID -ne 0 ]]; then
     # Attempt to use sudo if not root
     echo "Attempting package updates with sudo..."
     if command -v apt &>/dev/null; then
       sudo apt update && sudo apt upgrade -y
     elif command -v yum &>/dev/null; then
       sudo yum update -y
     elif command -v dnf &>/dev/null; then # Add dnf support for newer Fedora/RHEL
       sudo dnf update -y
     else
       echo "Error: Package manager (apt, yum, dnf) not found. Cannot perform updates."
       echo "-------------------------------"
       return 1 # Indicate failure
     fi
  else
    # Running as root directly
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
      return 1 # Indicate failure
    fi
  fi
  
  if [ $? -eq 0 ]; then
    echo "--- Package updates finished successfully ---"
  else
     echo "--- Package updates finished with errors ---"
  fi
  echo "-------------------------------"
  return 0 # Return 0 even on errors for now to let report generate, adjust if needed
}

# 3.2 Log Rotation & Archiving
rotate_logs() {
  echo "--- Rotating logs ---"
  local state_file="./logrotate.state"
  local config_file="./logrotate.conf"
  
  if [ "$DRY_RUN" = true ]; then 
     echo "DRY RUN: Would rotate logs using $state_file and $config_file."
     echo "---------------------"
     return 0 # Assume success in dry run
  fi
  
  if [ ! -f "$config_file" ]; then
      echo "Error: Logrotate config file '$config_file' not found. Skipping log rotation."
      echo "---------------------"
      return 1
  fi
  
  # Ensure the state file exists or logrotate might complain the first time
  touch "$state_file"
  
  # logrotate command itself will output its status/errors
  logrotate --state "$state_file" "$config_file"
  
  # Logrotate can sometimes exit non-zero for non-fatal reasons (e.g., no logs found)
  # We'll check the exit code but not necessarily fail the whole script
  if [ $? -eq 0 ]; then
    echo "Log rotation finished successfully."
  else
     echo "Log rotation finished with potential issues. Check output above."
     # return 1 # Uncomment to make logrotate errors critical
  fi
  echo "---------------------"
}

# 3.3 Resource Monitoring - CPU & RAM
check_cpu_ram() {
  echo "--- CPU & RAM Usage ---"
  # Get CPU idle percentage from top, then calculate usage (supports varying top outputs)
  # Using awk to handle potential multiple spaces and get the correct field
  cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $NF}' | sed 's/%//') # NF is usually idle % field
  if [[ "$cpu_idle" == "id," ]]; then cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $(NF-1)}' | sed 's/,//'); fi # Fallback for different top outputs

  if [ -z "$cpu_idle" ] || ! [[ "$cpu_idle" =~ ^[0-9.]+$ ]]; then
     echo "CPU Usage: N/A (Error parsing top output)"
  else
     cpu_usage=$(awk "BEGIN { printf \"%.2f\", 100 - $cpu_idle }")
     echo "CPU Usage: ${cpu_usage}%"
  fi

  # Get Memory used percentage from free
  # Using awk to calculate percentage (used/total * 100)
  mem_line=$(free -m | awk '/Mem:/')
   if [ -z "$mem_line" ]; then
     echo "Memory Usage: N/A (Error parsing free output)"
   else
     read -r _ total used free shared buff cache available <<< "$mem_line"
     if [ "$total" -gt 0 ]; then # Avoid division by zero
        mem_usage_pct=$(awk "BEGIN { printf \"%.2f\", ($used/$total)*100 }")
        echo "Memory Usage: ${mem_usage_pct}%"
     else
        echo "Memory Usage: N/A (Total memory is zero)"
     fi
   fi
  echo "--------------------------"
}

# 3.3 Resource Monitoring - Disk Usage
check_disk() {
  echo "--- Disk Usage & Free Space ---"
  # Default threshold from settings.conf, default to 80 if variable not set
  local disk_threshold="${DISK_THRESHOLD:-80}" 
  
  # Print all mounted filesystems usage, excluding snap, loop, tmpfs, etc.
  # Using awk to filter lines and format output
  df -hP | awk 'NR==1 || ($0 ~ /^\/dev\// && !/snap/ && !/loop/ && !/tmpfs/)' 
  
  echo # Blank line for separation
  
  # Check root partition specifically and report if over threshold
  # Use 'awk' to get the usage percentage and available space for the root mount point '/'
  local root_info=$(df -hP / | awk 'NR>1 {print $4, $5}' | sed 's/%//') # Get Avail, Use%
  local root_avail=$(echo "$root_info" | awk '{print $1}')
  local root_usep=$(echo "$root_info" | awk '{print $2}')
  
  if [ -n "$root_usep" ] && [[ "$root_usep" =~ ^[0-9]+$ ]]; then # Check if valid usage percentage found
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

# 3.3 Resource Monitoring - Top Processes
top_procs() {
  echo "--- Top 2 Processes by CPU ---"
  # ps command to list processes by CPU usage, print header + top 2 (3 lines total)
  # Use '|| true' to prevent set -e from exiting if ps sorting fails or no processes are found
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n3 || true
  
  echo; # Add a blank line for separation
  
  echo "--- Top 2 Processes by Memory ---"
  # ps command to list processes by Memory usage, print header + top 2 (3 lines total)
  ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n3 || true
  echo "------------------------------"
}

# 3.4 Container Health Checks - Docker
check_docker() {
  echo "--- Docker Container Health ---"
  if ! command -v docker &>/dev/null; then
    echo "Docker CLI not found. Skipping Docker health checks."
    echo "------------------------------"
    return 0 # Not an error if Docker is not installed
  fi
  
  # Check if Docker daemon is running and accessible
  if ! docker info >/dev/null 2>&1; then
      echo "Docker daemon is not running or accessible. Skipping Docker health checks."
      echo "------------------------------"
      return 0 # Not an error if Docker is not running
  fi
  
  local running_containers=$(docker ps -q)
  
  if [ -z "$running_containers" ]; then
      echo "No running Docker containers found."
  else
      echo "Checking running containers:"
      echo "CONTAINER NAME : HEALTH STATUS"
      echo "----------------------------------"
      # Loop through running container IDs
      for c in $running_containers; do
        local name=$(docker inspect --format '{{.Name}}' "$c")
        # Use .State.Health.Status if HEALTHCHECK is defined, otherwise check .State.Status
        # Add error check for docker inspect
        local health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo "Error getting health")
        echo "${name#:} : ${health}" # Remove leading slash from container name
      done
  fi
  echo "------------------------------"
}

# 3.4 Container Health Checks - Kubernetes
check_k8s() {
  echo "--- Kubernetes Pods (Non-Running) ---"
  if ! command -v kubectl &>/dev/null; then
    echo "kubectl CLI not found. Skipping K8s checks."
    echo "-------------------------"
    return 0 # Not an error if kubectl is not installed
  fi
  
  # Test if kubectl can connect to a cluster (basic check)
  # Use --request-timeout for systems where kubectl might hang
  if ! kubectl version --client=true >/dev/null 2>&1 && ! kubectl cluster-info >/dev/null 2>&1 --request-timeout=5s ; then
     echo "kubectl cannot connect to a cluster or config is invalid. Skipping K8s checks."
     echo "-------------------------"
     return 0 # Not an error if cluster is not available
  fi
  
  echo "Checking for pods not in 'Running' phase across all namespaces:"
  # Get pods with status phase not equal to Running, show labels for context
  # Use '|| true' to prevent set -e from exiting if no pods are found or kubectl has minor output to stderr
  kubectl get pods --all-namespaces --field-selector=status.phase!=Running --show-labels || true
  
  # Check if the previous command actually found any non-running pods
  # We can re-run a simpler version and count lines, or rely on the output above.
  # Let's rely on the output above for now.
  
  # A more robust check would capture output and check if it contains more than just the header.
  # For simplicity now, if kubectl ran without a critical error, assume it printed status.
  # You could add: if [ $(kubectl get pods --all-namespaces --field-selector=status.phase!=Running -o name | wc -l) -eq 0 ]; then echo "All pods are in 'Running' phase or no pods found."; fi
  
  echo "-------------------------"
}

# 3.5 Report Generation
generate_report() {
  echo "--- Generating Report ---"
  # Set the report file path using the current date (YYYY-MM-DD)
  REPORT_FILE="logs/daily-report-$(date +%Y-%m-%d).txt"
  mkdir -p logs # Ensure logs directory exists
  
  echo "Generating report file: $REPORT_FILE"
  
  { # Start of grouped commands whose output is redirected to $REPORT_FILE
    echo "Automated System Maintenance Report for $(hostname)"
    echo "Generated on: $(date)"
    echo "======================================="
    echo
    
    echo "=== Package Update Status ==="
    # This section reports on the *attempt* to update, referring to the main log
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
    # Call the check functions - their output goes directly into the report file
    check_cpu_ram 
    echo; # Add blank line in the report file
    check_disk    
    echo
    
    echo "=== Top Processes ==="
    top_procs 
    echo
    
    echo "=== Container Health Checks ==="
    check_docker 
    echo; # Add blank line
    check_k8s    
    echo
    
    echo "======================================="
    echo "Report End."
    
  } > "$REPORT_FILE" # End of grouped commands, redirecting all their output

  # Check if the report file was actually created and has content (more than just header)
  if [ -s "$REPORT_FILE" ]; then
      echo "Report generated successfully: $REPORT_FILE"
      # Return the path of the generated report file by printing it
      echo "$REPORT_FILE"
      return 0
  else
      echo "Error: Report file '$REPORT_FILE' was not generated or is empty."
      REPORT_FILE="" # Clear the variable if generation failed
      return 1
  fi
  echo "-------------------------"
}


# --- Main Script Logic ---
# Orchestrate the function calls here
# This is what gets executed when you run the script

echo "Running core maintenance tasks and report generation..."

# You can decide the order. A common flow:
# 1. Perform maintenance tasks (updates, log rotation)
# 2. Run checks
# 3. Generate report compiling check results and noting maintenance attempts

# Perform maintenance tasks (these sections are skipped in --dry-run)
update_packages # Note: This requires sudo or passwordless sudo setup for the user running the script via cron
rotate_logs

# Generate the daily report (This will call all the check_* functions)
# The output of generate_report (the report file path) is captured here
GENERATED_REPORT_PATH=$(generate_report)

# --- End of Main Logic ---

echo "-----------------------------------------"
echo "Maintenance script finished at $(date)"