# Automated System Maintenance & Reporting Scripts

This repository contains a suite of Bash scripts designed to automate routine system maintenance tasks and generate a daily report file summarizing the system's status.

**Key Features:**

* Automates package updates (requires sudo).
* Manages log rotation for script-generated logs.
* Monitors system resources (CPU, RAM, Disk Usage, Top Processes).
* Checks the health of Docker containers.
* Identifies non-running Kubernetes pods.
* Generates a daily text report file with the results of the checks.
* Includes a dry-run mode for safe testing.

## Directory Structure

* `bin/`: Contains executable scripts (e.g., `maintenance.sh`).
* `config/`: Holds configuration files (`settings.conf`).
* `logs/`: Stores generated log files (`maintenance_*.log`, `maint_cron.log`) and daily report files (`daily-report-*.txt`).
* `logrotate.conf`: Configuration for user-level log rotation of script logs.
* `README.md`: This file providing project information.
* `.gitignore`: Specifies files and directories that Git should ignore.

## Prerequisites

Ensure the following commands and tools are installed and available in your system's PATH:

* **Bash (v4+)**: The shell used to run the scripts.
* **`logrotate`**: For managing log file rotation.
* **`git`**: For version control.
* **`docker` CLI**: Required for Docker container checks.
* **`kubectl` CLI**: Required for Kubernetes checks.
* **Standard Unix utilities**: `grep`, `awk`, `sed`, `top`, `free`, `df`, `ps`, `date`, `mkdir`, `chmod`, `tee`, etc. (usually present by default).
* **`sudo`**: Needed for package updates; passwordless sudo configured for package manager commands (`apt`, `yum`, `dnf`) is required for automated updates via cron.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone <repository_url> maintenance-scripts
    cd maintenance-scripts
    ```
    *(If you started the project manually, you already have the directory and Git initialized).*

2.  **Ensure script is executable:**
    ```bash
    chmod +x bin/maintenance.sh
    ```

3.  **Configure `config/settings.conf`:**
    Edit `config/settings.conf` to adjust settings like thresholds.
    ```ini
    # Maintenance Script Configuration Settings
    #
    DISK_THRESHOLD=80  # Percentage disk usage at which to include a warning in the report (used in check_disk)
    # Add other thresholds or configuration variables here as needed
    ```

4.  **Configure `logrotate.conf`:**
    Edit `logrotate.conf` to specify how script logs and report files should be rotated. **Remember to replace `/home/youruser/` with your actual home directory path.** Ensure the file permissions are correct (`chmod 644 logrotate.conf`).
    *(Refer to the logrotate.conf content provided in the previous steps).*

5.  **Address Prerequisites Configuration:**
    * Ensure Docker daemon is running and your user is in the `docker` group to run `docker` commands without `sudo`.
    * Ensure `kubectl` is configured correctly (`~/.kube/config`) and can connect to your Kubernetes cluster if you need those checks to work.
    * Fix any issues with your system's APT/YUM/DNF repositories (`sudo apt update` etc.) if package updates are failing.

## Usage

You can run the script manually from your project directory (`~/maintenance-scripts/`).

* **Run the full maintenance and report generation:**
    ```bash
    ./bin/maintenance.sh
    ```
    This will attempt package updates (if running as root or with sudo), rotate logs, run all checks, and generate the daily report file in the `logs/` directory.

* **Run in dry-run mode:**
    ```bash
    ./bin/maintenance.sh --dry-run
    ```
    This will simulate package updates and log rotation (printing what it *would* do) but will not perform these actions. It will still run the checks and generate the report file, allowing you to test the parsing and reporting logic safely.

## Configuration

The script reads settings from `config/settings.conf`. Currently, the main setting is:

* `DISK_THRESHOLD`: The percentage of disk usage on the root partition (`/`) that will trigger a `WARNING` message in the report. Default is 80 if not set.

Add other configuration variables here as your script grows.

## Scheduling 

To automate the script, you will typically use cron. Add an entry to your user's crontab (`crontab -e`) to run the script at your desired interval (e.g., daily at midnight).

```cron
# Example: Run maintenance and report daily at 00:00
0 0 * * * /home/youruser/maintenance-scripts/bin/maintenance.sh >> /home/youruser/maintenance-scripts/logs/maint_cron.log 2>&1