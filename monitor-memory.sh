#!/bin/bash

################################################################################
# Dokodemo Memory Monitor and Auto-Heal Script
#
# Description: Monitors Xray process memory usage and performs graceful restart
#              when memory threshold is exceeded to prevent system overload
#
# Usage:
#   # Manual run
#   sudo ./monitor-memory.sh
#
#   # Add to crontab for automatic monitoring every 5 minutes
#   */5 * * * * /home/user/x-ui-settings-update/monitor-memory.sh >> /var/log/x-ui-memory-monitor.log 2>&1
#
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Memory threshold in percentage (default: 80%)
# If xray process uses more than this % of system memory, restart will be triggered
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-80}

# Minimum time between restarts in seconds (default: 300 = 5 minutes)
# Prevents restart loops
MIN_RESTART_INTERVAL=300

# Maximum restarts per hour (default: 6)
# Safety limit to prevent excessive restarts
MAX_RESTARTS_PER_HOUR=6

# Log file
LOG_FILE="/var/log/x-ui-memory-monitor.log"

# Lock file to prevent concurrent runs
LOCK_FILE="/var/run/x-ui-memory-monitor.lock"

# Restart history file
RESTART_HISTORY="/var/lib/x-ui-memory-monitor.history"

################################################################################
# COLORS
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - ${message}" | tee -a "${LOG_FILE}"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}" | tee -a "${LOG_FILE}"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}" | tee -a "${LOG_FILE}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}" | tee -a "${LOG_FILE}"
            ;;
        *)
            echo "${timestamp} - ${message}" | tee -a "${LOG_FILE}"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

# Acquire lock to prevent concurrent runs
acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")

        # Check if process is still running
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log WARN "Another instance is already running (PID: ${lock_pid})"
            exit 0
        else
            # Stale lock file, remove it
            rm -f "${LOCK_FILE}"
        fi
    fi

    echo $$ > "${LOCK_FILE}"
}

# Release lock
release_lock() {
    rm -f "${LOCK_FILE}"
}

# Cleanup on exit
cleanup() {
    release_lock
}

trap cleanup EXIT

################################################################################
# XRAY PROCESS FUNCTIONS
################################################################################

# Get Xray process PID
get_xray_pid() {
    local pid=""

    # Try multiple process names
    pid=$(pgrep -x "xray-linux-amd64" || pgrep -x "xray" || pgrep -f "xray" | head -1 || echo "")

    echo "${pid}"
}

# Get process memory usage in MB
get_process_memory_mb() {
    local pid=$1

    if [[ -z "${pid}" ]]; then
        echo "0"
        return
    fi

    # Get RSS (Resident Set Size) in KB and convert to MB
    local mem_kb=$(ps -p "${pid}" -o rss= 2>/dev/null | awk '{print $1}' || echo "0")
    local mem_mb=$((mem_kb / 1024))

    echo "${mem_mb}"
}

# Get process memory usage in percentage
get_process_memory_percent() {
    local pid=$1

    if [[ -z "${pid}" ]]; then
        echo "0"
        return
    fi

    # Get %MEM
    local mem_percent=$(ps -p "${pid}" -o %mem= 2>/dev/null | awk '{print int($1)}' || echo "0")

    echo "${mem_percent}"
}

# Get total system memory in MB
get_total_memory_mb() {
    local total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mb=$((total_kb / 1024))

    echo "${total_mb}"
}

################################################################################
# RESTART MANAGEMENT FUNCTIONS
################################################################################

# Check if restart is allowed based on rate limiting
is_restart_allowed() {
    # Create history directory if needed
    mkdir -p "$(dirname "${RESTART_HISTORY}")"

    # Create history file if it doesn't exist
    if [[ ! -f "${RESTART_HISTORY}" ]]; then
        touch "${RESTART_HISTORY}"
        return 0
    fi

    local current_time=$(date +%s)
    local one_hour_ago=$((current_time - 3600))

    # Count restarts in the last hour
    local restart_count=0
    while IFS= read -r line; do
        local restart_time=$(echo "${line}" | awk '{print $1}')

        if [[ "${restart_time}" -gt "${one_hour_ago}" ]]; then
            ((restart_count++))
        fi
    done < "${RESTART_HISTORY}"

    # Check if we've hit the hourly limit
    if [[ ${restart_count} -ge ${MAX_RESTARTS_PER_HOUR} ]]; then
        log ERROR "Restart limit reached: ${restart_count} restarts in the last hour"
        log ERROR "Maximum allowed: ${MAX_RESTARTS_PER_HOUR} per hour"
        log ERROR "Skipping restart to prevent restart loop"
        return 1
    fi

    # Check minimum interval since last restart
    if [[ -s "${RESTART_HISTORY}" ]]; then
        local last_restart=$(tail -1 "${RESTART_HISTORY}" | awk '{print $1}')
        local time_since_last=$((current_time - last_restart))

        if [[ ${time_since_last} -lt ${MIN_RESTART_INTERVAL} ]]; then
            log WARN "Too soon since last restart (${time_since_last}s ago)"
            log WARN "Minimum interval: ${MIN_RESTART_INTERVAL}s"
            return 1
        fi
    fi

    return 0
}

# Record restart in history
record_restart() {
    local mem_mb=$1
    local mem_percent=$2
    local current_time=$(date +%s)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "${current_time} ${timestamp} ${mem_mb}MB ${mem_percent}%" >> "${RESTART_HISTORY}"

    # Keep only last 100 entries
    if [[ $(wc -l < "${RESTART_HISTORY}") -gt 100 ]]; then
        tail -100 "${RESTART_HISTORY}" > "${RESTART_HISTORY}.tmp"
        mv "${RESTART_HISTORY}.tmp" "${RESTART_HISTORY}"
    fi
}

# Perform graceful restart of x-ui service
graceful_restart_xui() {
    log WARN "Initiating graceful restart of x-ui service..."

    # Check if x-ui service exists
    if ! systemctl list-units --full -all | grep -q "x-ui.service"; then
        log ERROR "x-ui service not found"
        return 1
    fi

    # Perform graceful restart
    # This sends SIGTERM to allow processes to clean up
    if systemctl restart x-ui; then
        log SUCCESS "x-ui service restarted successfully"

        # Wait a bit for service to stabilize
        sleep 5

        # Verify service is running
        if systemctl is-active --quiet x-ui; then
            log SUCCESS "x-ui service is active and running"

            # Get new PID and memory
            local new_pid=$(get_xray_pid)
            if [[ -n "${new_pid}" ]]; then
                local new_mem_mb=$(get_process_memory_mb "${new_pid}")
                local new_mem_percent=$(get_process_memory_percent "${new_pid}")
                log INFO "New Xray process: PID=${new_pid}, Memory=${new_mem_mb}MB (${new_mem_percent}%)"
            fi

            return 0
        else
            log ERROR "x-ui service failed to start after restart"
            return 1
        fi
    else
        log ERROR "Failed to restart x-ui service"
        return 1
    fi
}

################################################################################
# MONITORING FUNCTIONS
################################################################################

# Main monitoring function
monitor_memory() {
    log INFO "=== Memory Monitoring Check Started ==="

    # Get Xray PID
    local xray_pid=$(get_xray_pid)

    if [[ -z "${xray_pid}" ]]; then
        log ERROR "Xray process not found"
        log WARN "Is x-ui service running? Check: systemctl status x-ui"
        return 1
    fi

    # Get memory statistics
    local mem_mb=$(get_process_memory_mb "${xray_pid}")
    local mem_percent=$(get_process_memory_percent "${xray_pid}")
    local total_mem_mb=$(get_total_memory_mb)

    log INFO "Xray Process Status:"
    log INFO "  PID: ${xray_pid}"
    log INFO "  Memory Usage: ${mem_mb}MB / ${total_mem_mb}MB (${mem_percent}%)"
    log INFO "  Threshold: ${MEMORY_THRESHOLD}%"

    # Check if memory threshold is exceeded
    if [[ ${mem_percent} -ge ${MEMORY_THRESHOLD} ]]; then
        log WARN "Memory threshold exceeded: ${mem_percent}% >= ${MEMORY_THRESHOLD}%"

        # Check if restart is allowed
        if is_restart_allowed; then
            log WARN "Attempting to recover by restarting x-ui service..."

            if graceful_restart_xui; then
                # Record the restart
                record_restart "${mem_mb}" "${mem_percent}"
                log SUCCESS "Memory recovery completed successfully"
                return 0
            else
                log ERROR "Memory recovery failed"
                return 1
            fi
        else
            log ERROR "Restart not allowed due to rate limiting"
            log ERROR "Please check for underlying issues causing frequent restarts"
            return 1
        fi
    else
        log SUCCESS "Memory usage is normal: ${mem_percent}% < ${MEMORY_THRESHOLD}%"
        return 0
    fi
}

# Show restart history
show_restart_history() {
    echo ""
    echo "=== Restart History ==="

    if [[ ! -f "${RESTART_HISTORY}" ]] || [[ ! -s "${RESTART_HISTORY}" ]]; then
        echo "No restart history found"
        return
    fi

    echo "Last 10 restarts:"
    echo "----------------------------------------"
    echo "Timestamp              Memory"
    echo "----------------------------------------"
    tail -10 "${RESTART_HISTORY}" | while read -r line; do
        local timestamp=$(echo "${line}" | awk '{print $2, $3}')
        local memory=$(echo "${line}" | awk '{print $4, $5}')
        printf "%-20s %s\n" "${timestamp}" "${memory}"
    done
    echo "----------------------------------------"

    # Count restarts in last hour
    local current_time=$(date +%s)
    local one_hour_ago=$((current_time - 3600))
    local restart_count=0

    while IFS= read -r line; do
        local restart_time=$(echo "${line}" | awk '{print $1}')
        if [[ "${restart_time}" -gt "${one_hour_ago}" ]]; then
            ((restart_count++))
        fi
    done < "${RESTART_HISTORY}"

    echo ""
    echo "Restarts in last hour: ${restart_count}/${MAX_RESTARTS_PER_HOUR}"
}

################################################################################
# MAIN FUNCTION
################################################################################

main() {
    # Parse command line arguments
    case "${1:-monitor}" in
        monitor)
            check_root
            acquire_lock

            # Initialize log file
            mkdir -p "$(dirname "${LOG_FILE}")"
            touch "${LOG_FILE}"

            # Run monitoring
            monitor_memory
            ;;

        history)
            show_restart_history
            ;;

        status)
            local xray_pid=$(get_xray_pid)

            if [[ -z "${xray_pid}" ]]; then
                echo "Xray process: NOT RUNNING"
                exit 1
            fi

            local mem_mb=$(get_process_memory_mb "${xray_pid}")
            local mem_percent=$(get_process_memory_percent "${xray_pid}")
            local total_mem_mb=$(get_total_memory_mb)

            echo "Xray Process Status:"
            echo "  PID: ${xray_pid}"
            echo "  Memory: ${mem_mb}MB / ${total_mem_mb}MB (${mem_percent}%)"
            echo "  Threshold: ${MEMORY_THRESHOLD}%"

            if [[ ${mem_percent} -ge ${MEMORY_THRESHOLD} ]]; then
                echo "  Status: ⚠️  WARNING - Above threshold"
                exit 2
            else
                echo "  Status: ✓ OK"
                exit 0
            fi
            ;;

        --help|-h)
            cat << EOF
Dokodemo Memory Monitor and Auto-Heal Script

Usage: $0 [COMMAND]

Commands:
  monitor    Monitor memory and restart if needed (default)
  status     Show current memory status
  history    Show restart history
  --help     Show this help message

Environment Variables:
  MEMORY_THRESHOLD    Memory threshold percentage (default: 80)
                      Example: MEMORY_THRESHOLD=70 $0 monitor

Crontab Setup:
  # Monitor every 5 minutes
  */5 * * * * /home/user/x-ui-settings-update/monitor-memory.sh monitor >> /var/log/x-ui-memory-monitor.log 2>&1

  # Or use systemd timer (recommended)
  sudo systemctl enable --now x-ui-memory-monitor.timer

Files:
  Log file: ${LOG_FILE}
  History: ${RESTART_HISTORY}
  Lock file: ${LOCK_FILE}

Examples:
  # Check current status
  $0 status

  # Run monitoring once
  sudo $0 monitor

  # Show restart history
  $0 history

  # Custom threshold (70%)
  MEMORY_THRESHOLD=70 sudo $0 monitor

EOF
            ;;

        *)
            echo "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
