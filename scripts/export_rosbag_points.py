#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import numpy as np
import rosbag2_py
import yaml
from rclpy.serialization import deserialize_message
from sensor_msgs.msg import PointCloud2
from sensor_msgs_py import point_cloud2


DEFAULT_FIELDS = ("x", "y", "z", "intensity", "ring", "timestamp")


def read_bag_metadata(bag_dir: Path) -> dict:
    metadata_path = bag_dir / "metadata.yaml"
    if not metadata_path.is_file():
        return {}
    with metadata_path.open("r", encoding="utf-8") as stream:
        metadata = yaml.safe_load(stream) or {}
    return metadata.get("rosbag2_bagfile_information", {})


def infer_storage_id(bag_dir: Path, metadata: dict) -> str:
    storage_id = metadata.get("storage_identifier")
    if storage_id:
        return str(storage_id)
    if any(bag_dir.glob("*.mcap")):
        return "mcap"
    if any(bag_dir.glob("*.db3")) or any(bag_dir.glob("*.db3.zstd")):
        return "sqlite3"
    return "mcap"


def create_reader(metadata: dict):
    compression_mode = str(metadata.get("compression_mode") or "").lower()
    if compression_mode in {"file", "message"}:
        return rosbag2_py.SequentialCompressionReader()
    return rosbag2_py.SequentialReader()


def stamp_to_ns(stamp) -> int:
    return int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)


def read_points_array(msg: PointCloud2, skip_nans: bool) -> np.ndarray:
    points = point_cloud2.read_points(msg, field_names=None, skip_nans=skip_nans)
    if isinstance(points, np.ndarray):
        return points
    return np.array(list(points))


def to_matrix(points: np.ndarray, requested_fields) -> tuple[np.ndarray, list[str]]:
    if points.size == 0:
        return np.empty((0, 0), dtype=np.float32), []

    if points.dtype.names:
        fields = [field for field in requested_fields if field in points.dtype.names]
        if not fields:
            raise RuntimeError(f"No requested fields found. Available fields: {points.dtype.names}")
        columns = [points[field].astype(np.float32, copy=False) for field in fields]
        return np.column_stack(columns).astype(np.float32, copy=False), fields

    matrix = np.asarray(points, dtype=np.float32)
    if matrix.ndim == 1:
        matrix = matrix.reshape(-1, 1)
    fields = list(requested_fields[: matrix.shape[1]])
    return matrix, fields


def write_pcd(path: Path, matrix: np.ndarray, fields: list[str]) -> None:
    if matrix.ndim != 2:
        raise RuntimeError("PCD writer expects a 2D matrix")

    fields = list(fields)
    matrix = matrix.astype("<f4", copy=False)
    count = matrix.shape[0]
    header = "\n".join(
        [
            "# .PCD v0.7 - Point Cloud Data file format",
            "VERSION 0.7",
            "FIELDS " + " ".join(fields),
            "SIZE " + " ".join(["4"] * len(fields)),
            "TYPE " + " ".join(["F"] * len(fields)),
            "COUNT " + " ".join(["1"] * len(fields)),
            f"WIDTH {count}",
            "HEIGHT 1",
            "VIEWPOINT 0 0 0 1 0 0 0",
            f"POINTS {count}",
            "DATA binary",
            "",
        ]
    )

    with path.open("wb") as f:
        f.write(header.encode("ascii"))
        matrix.tofile(f)


def export_bag(args) -> None:
    bag_dir = Path(args.bag).expanduser().resolve()
    out_dir = Path(args.out).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    metadata = read_bag_metadata(bag_dir)
    reader = create_reader(metadata)
    storage_options = rosbag2_py.StorageOptions(
        uri=str(bag_dir),
        storage_id=args.storage_id or infer_storage_id(bag_dir, metadata),
    )
    converter_options = rosbag2_py.ConverterOptions(
        input_serialization_format="cdr",
        output_serialization_format="cdr",
    )
    reader.open(storage_options, converter_options)

    requested_fields = tuple(args.fields.split(","))
    manifest_path = out_dir / "manifest.jsonl"
    frame_index = 0
    exported = 0

    with manifest_path.open("w", encoding="utf-8") as manifest:
        while reader.has_next():
            topic, data, bag_timestamp_ns = reader.read_next()
            if topic != args.topic:
                continue
            if frame_index % args.every != 0:
                frame_index += 1
                continue

            msg = deserialize_message(data, PointCloud2)
            points = read_points_array(msg, args.skip_nans)
            matrix, fields = to_matrix(points, requested_fields)
            header_stamp_ns = stamp_to_ns(msg.header.stamp)

            stem = f"frame_{frame_index:06d}_{header_stamp_ns}"
            if args.format == "npy":
                output_path = out_dir / f"{stem}.npy"
                np.save(output_path, matrix)
            elif args.format == "npz":
                output_path = out_dir / f"{stem}.npz"
                np.savez_compressed(output_path, points=matrix, fields=np.asarray(fields))
            elif args.format == "bin":
                output_path = out_dir / f"{stem}.bin"
                bin_fields = [field for field in ("x", "y", "z", "intensity") if field in fields]
                if len(bin_fields) != 4:
                    raise RuntimeError(f"BIN export needs x,y,z,intensity. Available fields: {fields}")
                bin_matrix, _ = to_matrix(points, bin_fields)
                bin_matrix.astype("<f4", copy=False).tofile(output_path)
            elif args.format == "pcd":
                output_path = out_dir / f"{stem}.pcd"
                write_pcd(output_path, matrix, fields)
            else:
                raise RuntimeError(f"Unsupported format: {args.format}")

            manifest.write(
                json.dumps(
                    {
                        "frame_index": frame_index,
                        "topic": topic,
                        "bag_timestamp_ns": int(bag_timestamp_ns),
                        "header_stamp_ns": header_stamp_ns,
                        "point_count": int(matrix.shape[0]),
                        "fields": fields,
                        "path": str(output_path),
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
            exported += 1
            frame_index += 1

            if args.max_frames and exported >= args.max_frames:
                break

    print(f"Exported {exported} frames to {out_dir}")
    print(f"Manifest: {manifest_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export PointCloud2 messages from a ROS2 bag.")
    parser.add_argument("--bag", required=True, help="ROS2 bag directory")
    parser.add_argument("--topic", default="/rslidar_points", help="PointCloud2 topic")
    parser.add_argument("--out", required=True, help="Output directory")
    parser.add_argument("--format", choices=("npy", "npz", "bin", "pcd"), default="npy")
    parser.add_argument("--storage-id", default="", help="mcap or sqlite3. Empty means infer from files.")
    parser.add_argument("--fields", default=",".join(DEFAULT_FIELDS), help="Comma-separated fields to export")
    parser.add_argument("--skip-nans", action="store_true", help="Drop NaN points")
    parser.add_argument("--every", type=int, default=1, help="Export every Nth frame")
    parser.add_argument("--max-frames", type=int, default=0, help="0 means no limit")
    args = parser.parse_args()

    if args.every < 1:
        raise SystemExit("--every must be >= 1")

    export_bag(args)


if __name__ == "__main__":
    main()
