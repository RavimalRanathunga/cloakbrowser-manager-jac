#!/bin/bash
# usage: tools/guarded.sh <logfile> <cpus> <command...>
# Runs the command pinned to <cpus> (taskset list, e.g. 0-1), samples system memory every 0.2s,
# kills the process group when MemAvailable < 500MB, and records the peak system memory used.
LOG="$1"; CPUS="$2"; shift 2
setsid taskset -c "$CPUS" bash -c "$*" > "$LOG" 2>&1 &
PID=$!
TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
PEAK=0
while kill -0 $PID 2>/dev/null; do
  AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  USED=$((TOTAL-AVAIL)); [ $USED -gt $PEAK ] && PEAK=$USED
  if [ "$AVAIL" -lt ${MEM_FLOOR:-500} ]; then
    echo "WATCHDOG: MemAvailable=${AVAIL}MB, killing group $PID" >> "$LOG"
    kill -9 -- -$PID 2>/dev/null; break
  fi
  sleep 0.2
done
wait $PID 2>/dev/null; echo "EXIT=$? PEAK_SYSTEM_USED_MB=$PEAK (baseline before: see free)" >> "$LOG"
