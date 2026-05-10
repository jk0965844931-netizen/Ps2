"""Generate safe iPSX2 performance profiles.

The profiles intentionally avoid game-specific hacks.  They describe runtime
preferences that a launcher or settings migrator can translate into emulator
configuration values while keeping a predictable, testable contract.
"""

from __future__ import annotations

import json
import os
import tempfile
from copy import deepcopy
from pathlib import Path
from typing import Any

PRESETS: dict[str, dict[str, Any]] = {
    "performance": {
        "description": "Prioritise throughput and input latency on capable hardware.",
        "cpu": {
            "worker_threads": "auto",
            "max_worker_threads": 6,
            "prefer_big_cores": True,
            "spin_wait_budget_us": 250,
        },
        "gpu": {
            "async_pipeline_compilation": True,
            "shader_cache": True,
            "texture_upload_batching": True,
            "frame_latency_limit": 1,
        },
        "emulation": {
            "safe_speed_hacks": True,
            "strict_memory_checks": False,
            "deterministic_timing": False,
        },
        "frame_pacing": {
            "enabled": True,
            "mode": "low_latency",
            "max_jitter_ms": 1.75,
        },
    },
    "balanced": {
        "description": "Prefer smooth gameplay while keeping broad compatibility.",
        "cpu": {
            "worker_threads": "auto",
            "max_worker_threads": 4,
            "prefer_big_cores": True,
            "spin_wait_budget_us": 100,
        },
        "gpu": {
            "async_pipeline_compilation": True,
            "shader_cache": True,
            "texture_upload_batching": True,
            "frame_latency_limit": 2,
        },
        "emulation": {
            "safe_speed_hacks": True,
            "strict_memory_checks": True,
            "deterministic_timing": False,
        },
        "frame_pacing": {
            "enabled": True,
            "mode": "smooth",
            "max_jitter_ms": 2.5,
        },
    },
    "compatibility": {
        "description": "Reduce risky optimisations for games that expose timing bugs.",
        "cpu": {
            "worker_threads": "auto",
            "max_worker_threads": 2,
            "prefer_big_cores": False,
            "spin_wait_budget_us": 0,
        },
        "gpu": {
            "async_pipeline_compilation": False,
            "shader_cache": True,
            "texture_upload_batching": False,
            "frame_latency_limit": 3,
        },
        "emulation": {
            "safe_speed_hacks": False,
            "strict_memory_checks": True,
            "deterministic_timing": True,
        },
        "frame_pacing": {
            "enabled": True,
            "mode": "stable",
            "max_jitter_ms": 4.0,
        },
    },
}


def _auto_worker_threads(cpu_threads: int, max_worker_threads: int) -> int:
    """Choose enough workers for parallelism without starving the emulation thread."""

    if cpu_threads <= 2:
        return 1

    # Keep at least one logical CPU free for the main EE/IO/UI work.  Capping the
    # worker pool avoids oversubscription, which often shows up as frame-time
    # spikes even when average FPS looks good.
    return max(1, min(cpu_threads - 1, max_worker_threads))


def build_profile(preset: str = "balanced", *, cpu_threads: int | None = None) -> dict[str, Any]:
    """Return a concrete profile for *preset* using the current host CPU count.

    Args:
        preset: One of :data:`PRESETS`.
        cpu_threads: Optional logical CPU count override, mainly for tests.

    Raises:
        ValueError: If the requested preset is unknown or cpu_threads is invalid.
    """

    if preset not in PRESETS:
        valid = ", ".join(sorted(PRESETS))
        raise ValueError(f"unknown preset '{preset}'. Valid presets: {valid}")

    detected_threads = os.cpu_count() if cpu_threads is None else cpu_threads
    if detected_threads is None:
        detected_threads = 2
    if detected_threads < 1:
        raise ValueError("cpu_threads must be greater than zero")

    profile = deepcopy(PRESETS[preset])
    cpu = profile["cpu"]
    cpu["detected_threads"] = detected_threads
    cpu["worker_threads"] = _auto_worker_threads(detected_threads, cpu["max_worker_threads"])
    profile["preset"] = preset
    profile["schema_version"] = 1
    return profile


def write_profile(config_dir: str | Path, profile: dict[str, Any]) -> Path:
    """Atomically write *profile* to ``ipsx2-performance.json`` in *config_dir*."""

    destination_dir = Path(config_dir)
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / "ipsx2-performance.json"

    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=destination_dir,
        delete=False,
        prefix=".ipsx2-performance-",
        suffix=".tmp",
    ) as handle:
        json.dump(profile, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temporary_name = handle.name

    os.replace(temporary_name, destination)
    return destination
