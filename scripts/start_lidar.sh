#!/usr/bin/env bash
set -euo pipefail

WS_DIR="/mnt/e/project/lidar-sdk/ros2_ws"

unset PYTHONHOME
unset PYTHONPATH
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

set +u
source /opt/ros/jazzy/setup.bash
source "${WS_DIR}/install/setup.bash"
set -u

ros2 launch rslidar_sdk start.py
