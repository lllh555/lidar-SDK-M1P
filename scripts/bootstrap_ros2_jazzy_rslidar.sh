#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/mnt/e/project/lidar-sdk"
WS_DIR="${PROJECT_DIR}/ros2_ws"
SRC_DIR="${WS_DIR}/src"

if [ -n "${CONDA_PREFIX:-}" ] || [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
  echo "[0/7] Detected conda environment; forcing system Python for ROS2 build"
fi
unset PYTHONHOME
unset PYTHONPATH
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

echo "[1/7] Checking Ubuntu version"
if command -v lsb_release >/dev/null 2>&1; then
  lsb_release -a
fi

echo "[2/7] Installing base tools"
sudo apt update
sudo apt install -y software-properties-common curl gnupg lsb-release git
sudo add-apt-repository -y universe

echo "[3/7] Configuring ROS2 Jazzy apt source"
sudo install -d -m 0755 /usr/share/keyrings
if [ ! -f /usr/share/keyrings/ros-archive-keyring.gpg ]; then
  curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    | sudo tee /usr/share/keyrings/ros-archive-keyring.gpg >/dev/null
fi

ROS_LIST="/etc/apt/sources.list.d/ros2.list"
ROS_ENTRY="deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main"
if [ ! -f "${ROS_LIST}" ] || ! grep -Fq "${ROS_ENTRY}" "${ROS_LIST}"; then
  echo "${ROS_ENTRY}" | sudo tee "${ROS_LIST}" >/dev/null
fi

echo "[4/7] Installing ROS2 Jazzy and SDK dependencies"
sudo apt update
sudo apt install -y ros-jazzy-desktop python3-colcon-common-extensions ros-dev-tools python3-empy python3-yaml libyaml-cpp-dev libpcap-dev

echo "[5/7] Fetching RoboSense sources"
mkdir -p "${SRC_DIR}" "${PROJECT_DIR}/bags/packets" "${PROJECT_DIR}/bags/points" "${PROJECT_DIR}/exports/pcd" "${PROJECT_DIR}/exports/npy" "${PROJECT_DIR}/exports/npz" "${PROJECT_DIR}/exports/bin"

if [ ! -d "${SRC_DIR}/rslidar_sdk/.git" ]; then
  git clone https://github.com/RoboSense-LiDAR/rslidar_sdk.git "${SRC_DIR}/rslidar_sdk"
fi

if [ ! -d "${SRC_DIR}/rslidar_msg/.git" ]; then
  git clone https://github.com/RoboSense-LiDAR/rslidar_msg.git "${SRC_DIR}/rslidar_msg"
fi

git -C "${SRC_DIR}/rslidar_sdk" submodule update --init --recursive

echo "[6/7] Building workspace"
set +u
source /opt/ros/jazzy/setup.bash
set -u
cd "${WS_DIR}"
colcon build --symlink-install --cmake-args -DPython3_EXECUTABLE=/usr/bin/python3

echo "[7/7] Deployment complete"
echo "Next:"
echo "  source ${WS_DIR}/install/setup.bash"
echo "  ros2 launch rslidar_sdk start.py"
