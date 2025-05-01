#!/bin/bash
# Automated System Maintenance & Reporting Script

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Exit immediately if a command in a pipeline fails.
set -euo pipefail 

# --- Configuration Loading ---
# Load settings from config file.
# Source this *after* parsing basic arguments like --dry-run
# source config/settings.conf # Uncomment and populate config/settings.conf later

# --- Variables ---
# Variable to hold the path of the generated report file
REPORT_FILE=""

# --- Argument Parsing (Basic Placeholder) ---
# Add logic here later for --dry-run
echo "Script called with arguments: $@"

# --- Logging Setup (Basic Placeholder) ---
# For now, script output goes to stdout/stderr. Will redirect to a file later in Day 2.
echo "Starting maintenance script at $(date)"
echo "-----------------------------------------"

# --- Define Functions Below (Placeholders) ---

# 3.1 Package Updates
update_packages() { 
  echo "--- Running package updates ---"
  echo "Package update function placeholder."
  # Implement with apt/yum logic here (requires sudo)
  echo "-------------------------------"
}

# 3.2 Log Rotation & Archiving
rotate_logs() { 
  echo "--- Rotating logs ---"
  echo "Log rotation function placeholder."
   # Implement logrotate --state ... command here
  echo "---------------------"
}

# 3.3 Resource Monitoring
check_cpu_ram() { 
  echo "--- Checking CPU & RAM ---"
  echo "CPU/RAM check placeholder."
  # Implement with top/free parsing
  echo "--------------------------"
}

check_disk() { 
  echo "--- Checking Disk Usage ---"
  echo "Disk usage placeholder."
  # Implement with df parsing
  echo "---------------------------"
}

top_procs() { 
  echo "--- Checking Top Processes ---"
  echo "Top processes placeholder."
  # Implement with ps/top parsing
  echo "------------------------------"
}

# 3.4 Container Health Checks
check_docker() { 
  echo "--- Checking Docker Health ---"
  echo "Docker health check placeholder."
  # Implement with docker CLI commands
  echo "------------------------------"
}

check_k8s() { 
  echo "--- Checking K8s Pods ---"
  echo "Kubernetes check placeholder."
  # Implement with kubectl CLI commands
  echo "-------------------------" 
}

# 3.5 Report Generation 
generate_report() {
  echo "--- Generating Report ---"
  echo "Report generation placeholder."
  # This function will call the check functions and write their output to a file
  # It should set the REPORT_FILE variable and return the file path
  echo "-------------------------"
  # Example of returning the path:
  # local generated_path="logs/some_report_$(date +%F).txt"
  # echo "$generated_path" # print the path
}

# Note: send_report function is removed in this version

# --- Main Script Logic ---
# Orchestrate the function calls here later in Day 2

echo "-----------------------------------------"
echo "Maintenance script finished at $(date)"