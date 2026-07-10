#!/usr/bin/env python3
"""Load the project YAML config and emit shell-safe variable assignments."""

import argparse
import shlex
from pathlib import Path

import yaml


STORAGE_IDS = {"mcap", "sqlite3"}
COMPRESSION_MODES = {"none", "storage", "file", "message"}
MCAP_COMPRESSION_PROFILES = {"zstd_fast", "zstd_small"}
EXPORT_FORMATS = {"npy", "npz", "bin", "pcd"}


def nested_get(data, keys, default=None):
    value = data
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            return default
        value = value[key]
    return value


def as_string(value, name):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        raise ValueError(f"{name} must be a scalar value")
    return str(value)


def as_non_negative_int(value, name):
    try:
        result = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be an integer") from exc
    if result < 0:
        raise ValueError(f"{name} must be >= 0")
    return result


def emit(name, value):
    print(f"{name}={shlex.quote(str(value))}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    args = parser.parse_args()

    with args.config.open("r", encoding="utf-8") as stream:
        config = yaml.safe_load(stream) or {}
    if not isinstance(config, dict):
        raise ValueError("The YAML root must be a mapping")

    project_dir = as_string(
        nested_get(config, ("project", "project_dir"), "/mnt/e/project/lidar-sdk"),
        "project.project_dir",
    )
    ros_distro = as_string(
        nested_get(config, ("project", "ros_distro"), "jazzy"),
        "project.ros_distro",
    )
    workspace_dir = as_string(
        nested_get(config, ("project", "workspace_dir"), f"{project_dir}/ros2_ws"),
        "project.workspace_dir",
    )

    storage_id = as_string(
        nested_get(config, ("recording", "storage_id"), "mcap"),
        "recording.storage_id",
    ).lower()
    if storage_id not in STORAGE_IDS:
        raise ValueError(f"recording.storage_id must be one of: {', '.join(sorted(STORAGE_IDS))}")

    compression_mode = as_string(
        nested_get(config, ("recording", "compression", "mode"), "file"),
        "recording.compression.mode",
    ).lower()
    if compression_mode not in COMPRESSION_MODES:
        raise ValueError(
            "recording.compression.mode must be one of: "
            + ", ".join(sorted(COMPRESSION_MODES))
        )
    compression_format = as_string(
        nested_get(config, ("recording", "compression", "format"), "zstd"),
        "recording.compression.format",
    ).lower()
    if compression_mode != "none" and not compression_format:
        raise ValueError("recording.compression.format is required when compression is enabled")
    compression_profile = as_string(
        nested_get(config, ("recording", "compression", "profile"), "zstd_fast"),
        "recording.compression.profile",
    ).lower()
    if compression_mode == "storage":
        if storage_id != "mcap":
            raise ValueError("recording.compression.mode=storage requires recording.storage_id=mcap")
        if compression_format != "zstd":
            raise ValueError("MCAP storage compression currently requires format=zstd")
        if compression_profile not in MCAP_COMPRESSION_PROFILES:
            raise ValueError(
                "recording.compression.profile must be one of: "
                + ", ".join(sorted(MCAP_COMPRESSION_PROFILES))
            )

    extra_topics = nested_get(config, ("recording", "extra_topics"), [])
    if not isinstance(extra_topics, list):
        raise ValueError("recording.extra_topics must be a YAML list")
    extra_topics = " ".join(as_string(topic, "recording.extra_topics[]") for topic in extra_topics)

    export_format = as_string(
        nested_get(config, ("export", "format"), "npy"), "export.format"
    ).lower()
    if export_format not in EXPORT_FORMATS:
        raise ValueError(f"export.format must be one of: {', '.join(sorted(EXPORT_FORMATS))}")

    values = {
        "PROJECT_DIR": project_dir,
        "ROS_DISTRO": ros_distro,
        "WS_DIR": workspace_dir,
        "POINT_TOPIC": as_string(
            nested_get(config, ("recording", "topic"), "/rslidar_points"),
            "recording.topic",
        ),
        "POINT_BAG_DIR": as_string(
            nested_get(config, ("recording", "output_dir"), f"{project_dir}/bags/points"),
            "recording.output_dir",
        ),
        "BAG_PREFIX": as_string(
            nested_get(config, ("recording", "bag_prefix"), "points"),
            "recording.bag_prefix",
        ),
        "BAG_STORAGE_ID": storage_id,
        "BAG_COMPRESSION_MODE": compression_mode,
        "BAG_COMPRESSION_FORMAT": compression_format,
        "BAG_COMPRESSION_PROFILE": compression_profile,
        "RECORD_START_TIME": as_string(
            nested_get(config, ("recording", "start_time"), ""),
            "recording.start_time",
        ),
        "RECORD_DURATION_SECONDS": as_non_negative_int(
            nested_get(config, ("recording", "duration_seconds"), 10),
            "recording.duration_seconds",
        ),
        "RECORD_EXTRA_TOPICS": extra_topics,
        "WAIT_FOR_TOPIC_SECONDS": as_non_negative_int(
            nested_get(config, ("recording", "wait_for_topic_seconds"), 20),
            "recording.wait_for_topic_seconds",
        ),
        "WAIT_FOR_TOPIC_QOS": as_string(
            nested_get(config, ("recording", "wait_for_topic_qos"), "sensor_data"),
            "recording.wait_for_topic_qos",
        ),
        "RECORD_STOP_SIGNAL": as_string(
            nested_get(config, ("recording", "stop_signal"), "TERM"),
            "recording.stop_signal",
        ),
        "RECORD_STOP_GRACE_SECONDS": as_non_negative_int(
            nested_get(config, ("recording", "stop_grace_seconds"), 20),
            "recording.stop_grace_seconds",
        ),
        "EXPORT_INPUT_BAG": as_string(
            nested_get(config, ("export", "input_bag"), "latest"),
            "export.input_bag",
        ),
        "EXPORT_OUTPUT_DIR": as_string(
            nested_get(config, ("export", "output_dir"), ""),
            "export.output_dir",
        ),
        "EXPORT_ROOT": as_string(
            nested_get(config, ("export", "output_root"), f"{project_dir}/exports"),
            "export.output_root",
        ),
        "EXPORT_FORMAT": export_format,
        "EXPORT_MAX_FRAMES": as_non_negative_int(
            nested_get(config, ("export", "max_frames"), 0),
            "export.max_frames",
        ),
    }

    for name, value in values.items():
        emit(name, value)


if __name__ == "__main__":
    main()
