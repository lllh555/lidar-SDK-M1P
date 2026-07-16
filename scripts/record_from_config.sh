#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="${LIDAR_RECORDING_CONFIG:-${SCRIPT_DIR}/../lidar_recording_config.yaml}"

if [ "${1:-}" = "--config" ]; then
  if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [--config /path/to/lidar_recording_config.yaml]"
    exit 2
  fi
  CONFIG_FILE="$2"
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--config /path/to/lidar_recording_config.yaml]"
  exit 2
fi

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
ROS_SETUP_FILE="${ROS_SETUP_FILE:-/opt/ros/${ROS_DISTRO}/setup.bash}"

if [ ! -f "${ROS_SETUP_FILE}" ]; then
  echo "ROS setup file not found: ${ROS_SETUP_FILE}"
  echo "Set ROS_SETUP_FILE or project.ros_distro to match this machine."
  exit 2
fi

set +u
source "${ROS_SETUP_FILE}"
source "${WS_DIR}/install/setup.bash"
set -u

if [ -n "${RECORD_START_TIME}" ]; then
  START_EPOCH="$(date -d "${RECORD_START_TIME}" +%s)"
  NOW_EPOCH="$(date +%s)"
  WAIT_SECONDS="$((START_EPOCH - NOW_EPOCH))"
  if [ "${WAIT_SECONDS}" -gt 0 ]; then
    echo "Waiting ${WAIT_SECONDS}s until ${RECORD_START_TIME}"
    sleep "${WAIT_SECONDS}"
  fi
fi

mkdir -p "${POINT_BAG_DIR}"

if [ "${WAIT_FOR_TOPIC_SECONDS}" -gt 0 ]; then
  echo "Waiting up to ${WAIT_FOR_TOPIC_SECONDS}s for one message on ${POINT_TOPIC} using QoS ${WAIT_FOR_TOPIC_QOS}"
  if ! timeout "${WAIT_FOR_TOPIC_SECONDS}" ros2 topic echo --once --qos-profile "${WAIT_FOR_TOPIC_QOS}" "${POINT_TOPIC}" >/dev/null; then
    echo "No message received on ${POINT_TOPIC}; recording aborted."
    echo "Checks:"
    echo "  ros2 topic list | grep rslidar"
    echo "  ros2 topic info -v ${POINT_TOPIC}"
    echo "  ros2 topic hz ${POINT_TOPIC} --window 30"
    echo "If ${POINT_TOPIC} is publishing but this pre-check still fails, set recording.wait_for_topic_seconds: 0 in lidar_recording_config.yaml."
    exit 1
  fi
else
  echo "Skipping pre-check for ${POINT_TOPIC}"
fi

TOPICS=("${POINT_TOPIC}")
if [ -n "${RECORD_EXTRA_TOPICS}" ]; then
  # shellcheck disable=SC2206
  EXTRA_TOPICS=(${RECORD_EXTRA_TOPICS})
  TOPICS+=("${EXTRA_TOPICS[@]}")
fi

BAG_ARGS=(--storage "${BAG_STORAGE_ID}")
if [ "${BAG_COMPRESSION_MODE}" = "storage" ]; then
  BAG_ARGS+=(--storage-preset-profile "${BAG_COMPRESSION_PROFILE}")
  echo "Compression: MCAP native ${BAG_COMPRESSION_FORMAT}/${BAG_COMPRESSION_PROFILE}"
elif [ -n "${BAG_COMPRESSION_MODE}" ] && [ "${BAG_COMPRESSION_MODE}" != "none" ]; then
  BAG_ARGS+=(--compression-mode "${BAG_COMPRESSION_MODE}" --compression-format "${BAG_COMPRESSION_FORMAT}")
  echo "Compression: rosbag2 ${BAG_COMPRESSION_MODE}/${BAG_COMPRESSION_FORMAT}"
else
  echo "Compression: disabled"
fi

record_once() {
  local out_dir="$1"
  local rec_pid
  local stop_deadline

  echo "Recording ${RECORD_DURATION_SECONDS}s to ${out_dir}"
  echo "Storage: ${BAG_STORAGE_ID}"
  echo "Topics: ${TOPICS[*]}"

  setsid ros2 bag record -o "${out_dir}" "${BAG_ARGS[@]}" --topics "${TOPICS[@]}" &
  rec_pid="$!"

  sleep "${RECORD_DURATION_SECONDS}"

  echo "Stopping recorder process group ${rec_pid} with SIG${RECORD_STOP_SIGNAL}"
  kill "-${RECORD_STOP_SIGNAL}" "-${rec_pid}" 2>/dev/null || kill "-${RECORD_STOP_SIGNAL}" "${rec_pid}" 2>/dev/null || true

  stop_deadline="$((SECONDS + RECORD_STOP_GRACE_SECONDS))"
  while kill -0 "${rec_pid}" 2>/dev/null; do
    if [ "${SECONDS}" -ge "${stop_deadline}" ]; then
      echo "Recorder did not stop after ${RECORD_STOP_GRACE_SECONDS}s; sending SIGKILL."
      kill -KILL "-${rec_pid}" 2>/dev/null || kill -KILL "${rec_pid}" 2>/dev/null || true
      break
    fi
    sleep 1
  done

  wait "${rec_pid}" || true

  if [ ! -f "${out_dir}/metadata.yaml" ]; then
    echo "Recording did not create metadata.yaml: ${out_dir}"
    return 1
  fi

  echo "Recording complete: ${out_dir}"
}

if [ "${RECORD_INTERVAL_SECONDS}" -eq 0 ]; then
  record_once "${POINT_BAG_DIR}/${BAG_PREFIX}_$(date +%Y%m%d_%H%M%S)"
  exit 0
fi

echo "Repeating recordings every ${RECORD_INTERVAL_SECONDS}s; repeat_count=0 means until stopped."
cycle=1
while [ "${RECORD_REPEAT_COUNT}" -eq 0 ] || [ "${cycle}" -le "${RECORD_REPEAT_COUNT}" ]; do
  cycle_start_epoch="$(date +%s)"
  record_once "${POINT_BAG_DIR}/${BAG_PREFIX}_$(date +%Y%m%d_%H%M%S)_$(printf '%04d' "${cycle}")"

  if [ "${RECORD_REPEAT_COUNT}" -ne 0 ] && [ "${cycle}" -eq "${RECORD_REPEAT_COUNT}" ]; then
    break
  fi

  next_start_epoch="$((cycle_start_epoch + RECORD_INTERVAL_SECONDS))"
  now_epoch="$(date +%s)"
  wait_seconds="$((next_start_epoch - now_epoch))"
  if [ "${wait_seconds}" -gt 0 ]; then
    echo "Waiting ${wait_seconds}s before recording $((cycle + 1))"
    sleep "${wait_seconds}"
  else
    echo "Recording duration exceeded the ${RECORD_INTERVAL_SECONDS}s interval; starting recording $((cycle + 1)) now."
  fi
  cycle="$((cycle + 1))"
done
