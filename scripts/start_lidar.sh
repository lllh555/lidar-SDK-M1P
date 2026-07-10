#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WS_DIR="${PROJECT_DIR}/ros2_ws"
LIDAR_CONFIG="${LIDAR_SDK_CONFIG:-${PROJECT_DIR}/config/rslidar_sdk_config.yaml}"

if [ ! -f "${LIDAR_CONFIG}" ]; then
  echo "Missing LiDAR config: ${LIDAR_CONFIG}"
  exit 2
fi

unset PYTHONHOME
unset PYTHONPATH
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

set +u
source /opt/ros/jazzy/setup.bash
source "${WS_DIR}/install/setup.bash"
set -u

ros2 run rslidar_sdk rslidar_sdk_node --ros-args -p "config_path:=${LIDAR_CONFIG}"
