#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${LIDAR_RECORDING_CONFIG:-${SCRIPT_DIR}/../lidar_recording_config.yaml}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --input BAG_DIR|latest   Input rosbag2 directory (default: YAML export.input_bag)
  --output OUT_DIR        Exact export output directory (default: YAML or automatic)
  --format npy|npz|bin|pcd
                           Output point-cloud format (default: YAML export.format)
  --max-frames N          Maximum frames; 0 exports all frames
  --topic TOPIC           PointCloud2 topic (default: YAML recording.topic)
  --config FILE           YAML config path
  -h, --help              Show this help
EOF
}

CLI_INPUT=""
CLI_OUTPUT=""
CLI_FORMAT=""
CLI_MAX_FRAMES=""
CLI_TOPIC=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      CLI_INPUT="${2:?--input requires a value}"
      shift 2
      ;;
    --output)
      CLI_OUTPUT="${2:?--output requires a value}"
      shift 2
      ;;
    --format)
      CLI_FORMAT="${2:?--format requires a value}"
      shift 2
      ;;
    --max-frames)
      CLI_MAX_FRAMES="${2:?--max-frames requires a value}"
      shift 2
      ;;
    --topic)
      CLI_TOPIC="${2:?--topic requires a value}"
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:?--config requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Missing config file: ${CONFIG_FILE}"
  exit 2
fi

unset PYTHONHOME
unset PYTHONPATH
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

if ! CONFIG_VALUES="$(/usr/bin/python3 "${SCRIPT_DIR}/load_lidar_config.py" "${CONFIG_FILE}")"; then
  echo "Failed to load config: ${CONFIG_FILE}"
  exit 2
fi
eval "${CONFIG_VALUES}"

BAG_ARG="${CLI_INPUT:-${EXPORT_INPUT_BAG}}"
FORMAT="${CLI_FORMAT:-${EXPORT_FORMAT}}"
MAX_FRAMES="${CLI_MAX_FRAMES:-${EXPORT_MAX_FRAMES}}"
TOPIC="${CLI_TOPIC:-${POINT_TOPIC}}"

case "${FORMAT}" in
  npy|npz|bin|pcd) ;;
  *)
    echo "Unsupported export format: ${FORMAT}. Use npy, npz, bin, or pcd."
    exit 2
    ;;
esac

if ! [[ "${MAX_FRAMES}" =~ ^[0-9]+$ ]]; then
  echo "--max-frames must be a non-negative integer"
  exit 2
fi

if [ "${BAG_ARG}" = "latest" ]; then
  BAG_DIR="$(ls -td "${POINT_BAG_DIR}/${BAG_PREFIX}_"* 2>/dev/null | head -1 || true)"
  if [ -z "${BAG_DIR}" ]; then
    echo "No bag found under ${POINT_BAG_DIR}"
    exit 1
  fi
else
  BAG_DIR="${BAG_ARG}"
fi

if [ ! -d "${BAG_DIR}" ]; then
  echo "Input bag directory does not exist: ${BAG_DIR}"
  exit 1
fi

BAG_NAME="$(basename "${BAG_DIR}")"
if [ -n "${CLI_OUTPUT}" ]; then
  OUT_DIR="${CLI_OUTPUT}"
elif [ -n "${EXPORT_OUTPUT_DIR}" ]; then
  OUT_DIR="${EXPORT_OUTPUT_DIR}"
else
  OUT_DIR="${EXPORT_ROOT}/${FORMAT}/${BAG_NAME}"
fi

set +u
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source "${WS_DIR}/install/setup.bash"
set -u

MAX_ARGS=()
if [ "${MAX_FRAMES}" -gt 0 ]; then
  MAX_ARGS=(--max-frames "${MAX_FRAMES}")
fi

echo "Input bag: ${BAG_DIR}"
echo "Output directory: ${OUT_DIR}"
echo "Format: ${FORMAT}"

python3 "${SCRIPT_DIR}/export_rosbag_points.py" \
  --bag "${BAG_DIR}" \
  --topic "${TOPIC}" \
  --format "${FORMAT}" \
  --out "${OUT_DIR}" \
  "${MAX_ARGS[@]}"
