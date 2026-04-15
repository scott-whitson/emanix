#!/bin/bash
# GPU utilization for AMD (sysfs)
busy_file=$(find /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)
if [[ -f "$busy_file" ]]; then
    cat "$busy_file"
else
    echo "N/A"
fi
