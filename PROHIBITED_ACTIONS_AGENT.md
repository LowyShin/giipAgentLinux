# GIIP Agent Development - Safety Checks & Prohibited Actions
> **WARNING**: READ THIS BEFORE MAKING ANY CHANGES TO AGENT SCRIPTS.

## 1. Do Not Create Infinite Loops
*   **Cause**: Disabling interval checks (`should_run_...`) during debugging and forgetting to restore them.
*   **Consequence**: The agent runs continuously in a tight loop, spamming the server with requests (DDOS-like behavior), filling up disk logs, and consuming 100% CPU.
*   **Rule**: **NEVER** disable interval checks in production code. If you must for local testing, adding a "TODO: REVERT" comment is not enough—you must verify the diff before committing.
*   **Safety Net**: Always ensure your loop has a `sleep` or a hard break condition.

## 2. Do Not Use Unsafe Shell Iterations
*   **Cause**: Iterating over a variable using `<<< "$var"` or command substitution without proper quoting or handling of empty/multiline strings.
*   **Consequence**: If the variable is malformed, the loop might spin infinitely or execute commands with empty arguments.
*   **Rule**: Use temporary files for complex iterations or `while read` loops with strict IFS handling.
    ```bash
    # BAD
    while read line; do ... done <<< "$(some_cmd)"

    # GOOD
    some_cmd > /tmp/tempfile
    while IFS= read -r line; do ... done < /tmp/tempfile
    rm /tmp/tempfile
    ```

## 3. Do Not Leave Debug Logs Dumped to Stderr
*   **Cause**: Using `echo "..." >&2` for debugging connectivity or variables.
*   **Consequence**: Fills up the cron/system logs or console buffer immediately. If inside a tight loop (see #1), this crashes the logging daemon.
*   **Rule**: Use the standard `log_message` function which handles log rotation and levels. Remove or comment out direct `echo` debugging before pushing.

## 4. Do Not Assume APIs Always Respond
*   **Cause**: Using `curl` or `wget` without timeouts.
*   **Consequence**: If the server hangs or drops packets (firewall), the agent process hangs indefinitely. These "zombie" processes accumulate over time (e.g., if triggered by cron), exhausting system resources (PID/FD limits).
*   **Rule**: Always use timeouts.
    ```bash
    curl --connect-timeout 10 --max-time 30 ...
    ```

## 5. Implement Self-Cleanup (Singleton Pattern)
*   **Cause**: Re-running the agent while a previous instance is stuck.
*   **Consequence**: Multiple agents fighting for resources, race conditions on log/state files, and double reporting.
*   **Rule**: The script MUST check for its own existing PIDs and terminate them on startup.
    ```bash
    # Example logic in giipAgent3.sh
    EXISTING_PIDS=$(pgrep -f "bash $SCRIPT_ABS_PATH" | grep -v "$CURRENT_PID")
    if [ -n "$EXISTING_PIDS" ]; then kill -9 $EXISTING_PIDS; fi
    ```
