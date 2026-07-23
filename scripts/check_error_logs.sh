#!/bin/bash
# Script to check error logs and create a task for Error Analyst if errors are found.

# Configuration
LOG_DIR="/var/log" # Adjust as needed, e.g., for specific app logs
KEYWORDS="ERROR|FAIL|CRITICAL"
SEARCH_DAYS=1 # Search logs modified in the last X days

# Path to dispatch directory for new tasks
DISPATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../giipdb/dispatch" && pwd)"

# Ensure DISPATCH_DIR exists
mkdir -p "$DISPATCH_DIR"

# Temporary file to store found errors
TEMP_ERROR_LOG=$(mktemp)

# Find log files and search for keywords
# Using find -mtime -1 to search files modified in the last 24 hours (less than 1 day old)
find "$LOG_DIR" -type f -name "*.log" -mtime -"$SEARCH_DAYS" -print0 | xargs -0 grep -H -i -E "$KEYWORDS" > "$TEMP_ERROR_LOG" || true

# Check if any errors were found
if [ -s "$TEMP_ERROR_LOG" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    TASK_FILE="${DISPATCH_DIR}/TASK_${TIMESTAMP}_ERROR_LOG_REVIEW.md"
    
    echo "# Task: Daily Error Log Review" > "$TASK_FILE"
    echo "**Task ID**: TASK_${TIMESTAMP}_ERROR_LOG_REVIEW" >> "$TASK_FILE"
    echo "**Status:** Pending" >> "$TASK_FILE"
    echo "**Priority**: High" >> "$TASK_FILE"
    echo "**Target Role**: Error Analyst" >> "$TASK_FILE"
    echo "**Created At**: $(date +"%Y%m%d %H:%M:%S")" >> "$TASK_FILE"
    echo "" >> "$TASK_FILE"
    echo "## Objective" >> "$TASK_FILE"
    echo "Review daily error logs and identify root causes for reported issues." >> "$TASK_FILE"
    echo "" >> "$TASK_FILE"
    echo "## Details" >> "$TASK_FILE"
    echo "The following error keywords were detected in logs modified within the last ${SEARCH_DAYS} day(s):" >> "$TASK_FILE"
    echo "```" >> "$TASK_FILE"
    cat "$TEMP_ERROR_LOG" >> "$TASK_FILE"
    echo "```" >> "$TASK_FILE"
    echo "" >> "$TASK_FILE"
    echo "## Action Items" >> "$TASK_FILE"
    echo "1. Analyze the reported errors." >> "$TASK_FILE"
    echo "2. Create specific tasks (if needed) for developers/DevOps to fix the identified issues." >> "$TASK_FILE"
    echo "3. Update the status of this task to 'Completed' after review." >> "$TASK_FILE"

    echo "Created new pending task for Error Analyst: $TASK_FILE"
else
    echo "No new error keywords found in logs from the last ${SEARCH_DAYS} day(s)."
fi

# Clean up temporary file
rm -f "$TEMP_ERROR_LOG"
