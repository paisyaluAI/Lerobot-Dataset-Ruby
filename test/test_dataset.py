#!/usr/bin/env python3
"""Validate a local LeRobotDataset v3.0 directory.

Usage:
    python3 test_dataset.py output_dataset/my_first_robot_dataset

If the ``lerobot`` package is installed, the script also tries to load the
 dataset through LeRobotDataset. PyArrow and OpenCV are used for independent
 structural checks.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pyarrow.parquet as pq

try:
    import cv2
except ImportError:
    cv2 = None


class DatasetValidationError(Exception):
    """Raised when the dataset does not satisfy the expected v3 invariants."""


def load_json(path: Path) -> dict:
    if not path.is_file():
        raise DatasetValidationError(f"Missing file: {path}")
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def validate_tasks(dataset_root: Path) -> int:
    tasks_parquet_path = dataset_root / "meta" / "tasks.parquet"
    if not tasks_parquet_path.is_file():
        raise DatasetValidationError(f"Missing file: {tasks_parquet_path}")

    table = pq.read_table(tasks_parquet_path)
    if "task_index" not in table.column_names and (
        table.schema.pandas_metadata is None or "task_index" not in str(table.schema.pandas_metadata)
    ):
        raise DatasetValidationError("meta/tasks.parquet missing task_index column")
    if len(table) == 0:
        raise DatasetValidationError("meta/tasks.parquet contains no tasks")
    return len(table)


def validate_dataset(dataset_root: Path) -> dict:
    info = load_json(dataset_root / "meta" / "info.json")
    if info.get("codebase_version") != "v3.0":
        raise DatasetValidationError(
            f"Expected codebase_version v3.0, got {info.get('codebase_version')!r}"
        )

    required_paths = (
        dataset_root / "data" / "chunk-000" / "file-000.parquet",
        dataset_root / "meta" / "episodes" / "chunk-000" / "file-000.parquet",
    )
    for path in required_paths:
        if not path.is_file():
            raise DatasetValidationError(f"Missing file: {path}")

    task_count = validate_tasks(dataset_root)
    data_table = pq.read_table(required_paths[0])
    episode_table = pq.read_table(required_paths[1])
    data_columns = set(data_table.column_names)
    episode_columns = set(episode_table.column_names)

    required_data_columns = {"episode_index", "frame_index", "action", "state", "timestamp"}
    required_episode_columns = {"episode_index", "tasks", "length"}
    missing_data = required_data_columns - data_columns
    missing_episodes = required_episode_columns - episode_columns
    if missing_data:
        raise DatasetValidationError(f"Missing data columns: {sorted(missing_data)}")
    if missing_episodes:
        raise DatasetValidationError(
            f"Missing episode columns: {sorted(missing_episodes)}"
        )

    frame_count = data_table.num_rows
    episode_count = episode_table.num_rows
    declared_frames = info.get("total_frames")
    declared_episodes = info.get("total_episodes")
    if declared_frames != frame_count:
        raise DatasetValidationError(
            f"total_frames={declared_frames} but data contains {frame_count} rows"
        )
    if declared_episodes != episode_count:
        raise DatasetValidationError(
            f"total_episodes={declared_episodes} but episode metadata contains "
            f"{episode_count} rows"
        )

    lengths = episode_table.column("length").to_pylist()
    if sum(lengths) != frame_count:
        raise DatasetValidationError(
            f"Episode lengths sum to {sum(lengths)}, but data contains {frame_count} rows"
        )

    video_relative_path = (
        info.get("data_files", {}).get("videos", {}).get("rgb")
        or (
            info.get("video_path")
            and info["video_path"].format(
                video_key="rgb", chunk_index=0, file_index=0
            )
        )
        or "videos/rgb/chunk-000/file-000.mp4"
    )
    if not video_relative_path:
        raise DatasetValidationError("info.json does not define the rgb video path")
    video_path = dataset_root / video_relative_path
    if not video_path.is_file() or video_path.stat().st_size == 0:
        raise DatasetValidationError(f"Missing or empty video: {video_path}")

    video_frames = None
    video_fps = None
    if cv2 is not None:
        capture = cv2.VideoCapture(str(video_path))
        if not capture.isOpened():
            raise DatasetValidationError(f"OpenCV cannot open video: {video_path}")
        video_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        video_fps = capture.get(cv2.CAP_PROP_FPS)
        capture.release()
        if video_frames < frame_count:
            raise DatasetValidationError(
                f"Video contains {video_frames} frames, but data contains {frame_count} rows"
            )
        expected_fps = float(info.get("fps", 0))
        if expected_fps > 0 and abs(video_fps - expected_fps) > 0.5:
            raise DatasetValidationError(
                f"Video FPS is {video_fps}, expected approximately {expected_fps}"
            )

    return {
        "episodes": episode_count,
        "frames": frame_count,
        "tasks": task_count,
        "video_frames": video_frames,
        "video_fps": video_fps,
    }


def validate_with_lerobot(dataset_root: Path) -> str:
    try:
        from lerobot.datasets.lerobot_dataset import LeRobotDataset
    except ImportError:
        return "LeRobotDataset import skipped: lerobot is not installed"

    try:
        dataset = LeRobotDataset(repo_id=dataset_root.name, root=str(dataset_root))
        if len(dataset) == 0:
            raise DatasetValidationError("LeRobotDataset loaded zero samples")
        return f"LeRobotDataset loaded successfully ({len(dataset)} samples)"
    except Exception as error:
        raise DatasetValidationError(f"LeRobotDataset load failed: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "dataset_root",
        nargs="?",
        default="output_dataset/robot_dataset",
        type=Path,
    )
    args = parser.parse_args()
    dataset_root = args.dataset_root.resolve()

    try:
        result = validate_dataset(dataset_root)
        lerobot_result = validate_with_lerobot(dataset_root)
    except DatasetValidationError as error:
        print(f"INVALID: {error}", file=sys.stderr)
        return 1

    print(f"VALID: {dataset_root}")
    print(json.dumps(result, indent=2))
    print(lerobot_result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
