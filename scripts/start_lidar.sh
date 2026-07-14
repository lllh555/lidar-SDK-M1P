#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WS_DIR="${PROJECT_DIR}/ros2_ws"
LIDAR_CONFIG="${LIDAR_SDK_CONFIG:-${PROJECT_DIR}/config/rslidar_sdk_config.yaml}"
ROS_DISTRO="${LIDAR_ROS_DISTRO:-${ROS_DISTRO:-jazzy}}"
ROS_SETUP_FILE="${ROS_SETUP_FILE:-/opt/ros/${ROS_DISTRO}/setup.bash}"

if [ ! -f "${LIDAR_CONFIG}" ]; then
  echo "Missing LiDAR config: ${LIDAR_CONFIG}"
  exit 2
fi

if [ ! -f "${ROS_SETUP_FILE}" ]; then
  echo "ROS setup file not found: ${ROS_SETUP_FILE}"
  echo "Set ROS_SETUP_FILE or LIDAR_ROS_DISTRO to match this machine."
  exit 2
fi

unset PYTHONHOME
unset PYTHONPATH
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

set +u
source "${ROS_SETUP_FILE}"
source "${WS_DIR}/install/setup.bash"
set -u

ros2 run rslidar_sdk rslidar_sdk_node --ros-args -p "config_path:=${LIDAR_CONFIG}"
