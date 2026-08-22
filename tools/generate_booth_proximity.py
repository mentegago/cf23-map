#!/usr/bin/env python3
"""Generate sparse walking distances between booths from data/map.json."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
import hashlib
import json
from pathlib import Path
import re
import sys


SCHEMA_VERSION = 1
MAX_DISTANCE = 32
MAX_NEIGHBORS = 48
BOOTH_PATTERN = re.compile(r"^([A-Z]+)-0*(\d+)([ab]?)$")
DIRECTIONS = ((-1, 0), (1, 0), (0, -1), (0, 1))


def canonical_booth(value: object) -> str | None:
    match = BOOTH_PATTERN.fullmatch(str(value).strip())
    if match is None:
        return None
    section, number, suffix = match.groups()
    return f"{section}-{int(number)}{suffix}"


def is_empty(grid: list[list[object]], row: int, col: int) -> bool:
    return (
        0 <= row < len(grid)
        and 0 <= col < len(grid[row])
        and not str(grid[row][col]).strip()
    )


def booth_access_points(
    grid: list[list[object]],
    cells: set[tuple[int, int]],
) -> set[tuple[int, int]]:
    access_points: set[tuple[int, int]] = set()
    for row, col in cells:
        for row_delta, col_delta in DIRECTIONS:
            adjacent_row = row + row_delta
            adjacent_col = col + col_delta
            if is_empty(grid, adjacent_row, adjacent_col):
                access_points.add((adjacent_row, adjacent_col))
                continue

            if not (
                0 <= adjacent_row < len(grid)
                and 0 <= adjacent_col < len(grid[adjacent_row])
            ):
                continue
            adjacent = str(grid[adjacent_row][adjacent_col]).strip()
            if adjacent not in {"a", "b"}:
                continue

            aisle_row = adjacent_row + row_delta
            aisle_col = adjacent_col + col_delta
            if is_empty(grid, aisle_row, aisle_col):
                access_points.add((aisle_row, aisle_col))
    return access_points


def distances_from(
    grid: list[list[object]],
    source: str,
    source_access: set[tuple[int, int]],
    booths_by_access: dict[tuple[int, int], set[str]],
) -> dict[str, int]:
    queue = deque((row, col, 0) for row, col in source_access)
    visited = set(source_access)
    distances: dict[str, int] = {}

    while queue:
        row, col, distance = queue.popleft()
        for booth in booths_by_access.get((row, col), ()):
            if booth != source:
                previous = distances.get(booth)
                if previous is None or distance < previous:
                    distances[booth] = distance

        if distance >= MAX_DISTANCE:
            continue
        next_distance = distance + 1
        for row_delta, col_delta in DIRECTIONS:
            next_row = row + row_delta
            next_col = col + col_delta
            position = (next_row, next_col)
            if position in visited or not is_empty(grid, next_row, next_col):
                continue
            visited.add(position)
            queue.append((next_row, next_col, next_distance))

    return distances


def generate(map_path: Path) -> dict[str, object]:
    map_bytes = map_path.read_bytes()
    grid = json.loads(map_bytes)
    cells_by_booth: dict[str, set[tuple[int, int]]] = defaultdict(set)
    for row, values in enumerate(grid):
        for col, value in enumerate(values):
            booth = canonical_booth(value)
            if booth is not None:
                cells_by_booth[booth].add((row, col))

    access_by_booth = {
        booth: booth_access_points(grid, cells)
        for booth, cells in cells_by_booth.items()
    }
    inaccessible = sorted(
        booth for booth, access in access_by_booth.items() if not access
    )
    if inaccessible:
        preview = ", ".join(inaccessible[:10])
        raise RuntimeError(
            f"{len(inaccessible)} booths have no aisle access points: {preview}"
        )

    booths_by_access: dict[tuple[int, int], set[str]] = defaultdict(set)
    for booth, access_points in access_by_booth.items():
        for position in access_points:
            booths_by_access[position].add(booth)

    booths = sorted(cells_by_booth)
    booth_indices = {booth: index for index, booth in enumerate(booths)}
    neighbors: list[list[list[int]]] = []
    for booth in booths:
        distances = distances_from(
            grid,
            booth,
            access_by_booth[booth],
            booths_by_access,
        )
        ordered = sorted(
            distances.items(), key=lambda item: (item[1], item[0])
        )[:MAX_NEIGHBORS]
        neighbors.append(
            [[booth_indices[target], distance] for target, distance in ordered]
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "map_sha256": hashlib.sha256(map_bytes).hexdigest(),
        "max_distance": MAX_DISTANCE,
        "max_neighbors": MAX_NEIGHBORS,
        "booths": booths,
        "neighbors": neighbors,
    }


def encoded(data: dict[str, object]) -> str:
    return json.dumps(data, separators=(",", ":"), ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the committed proximity data is stale.",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    map_path = project_root / "data" / "map.json"
    output_path = project_root / "data" / "booth-proximity.json"
    output = encoded(generate(map_path))

    if args.check:
        if not output_path.exists() or output_path.read_text(encoding="utf-8") != output:
            print(
                "data/booth-proximity.json is stale; run "
                "python tools/generate_booth_proximity.py",
                file=sys.stderr,
            )
            return 1
        print("data/booth-proximity.json is up to date")
        return 0

    output_path.write_text(output, encoding="utf-8", newline="\n")
    print(f"Wrote {output_path.relative_to(project_root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
