#!/usr/bin/env python3
"""Render Vecherinka artifact.commit JSONL events as DOT or SVG."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


def load_graph(path: Path, run_id: str | None = None) -> dict[str, Any]:
    nodes: dict[int, dict[str, Any]] = {}
    edges: Counter[tuple[int, int]] = Counter()
    run_ids: set[str] = set()
    commit_count = 0
    truncated_count = 0
    non_json_count = 0

    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                non_json_count += 1
                continue

            if not isinstance(record, dict):
                continue
            if record.get("event") != "artifact.commit":
                continue
            record_run_id = record.get("run_id")
            if isinstance(record_run_id, str):
                run_ids.add(record_run_id)
            if run_id is not None and record_run_id != run_id:
                continue
            if record.get("truncated"):
                truncated_count += 1
                continue

            fields = record.get("fields")
            if not isinstance(fields, dict) or "artifact_id" not in fields:
                raise ValueError(
                    f"{path}:{line_number}: artifact.commit missing fields")
            artifact_id = int(fields["artifact_id"])
            nodes[artifact_id] = {
                "artifact_dir": str(fields.get("artifact_dir", "")),
                "operation": str(fields.get("operation", "")),
                "flow_kind": str(fields.get("flow_kind", "")),
                "request_id": str(fields.get("request_id", "")),
                "missing": False,
            }
            predecessors = fields.get("predecessor_ids", [])
            if not isinstance(predecessors, list):
                raise ValueError(
                    f"{path}:{line_number}: predecessor_ids must be an array")
            for predecessor in predecessors:
                predecessor_id = int(predecessor)
                edges[(predecessor_id, artifact_id)] += 1
                nodes.setdefault(
                    predecessor_id,
                    {
                        "artifact_dir": "(not committed)",
                        "operation": "",
                        "flow_kind": "",
                        "request_id": "",
                        "missing": True,
                    },
                )
            commit_count += 1

    if run_id is None and len(run_ids) > 1:
        raise ValueError(
            "log contains multiple run_id values; pass --run-id to select one")

    return {
        "nodes": nodes,
        "edges": edges,
        "run_id": run_id or next(iter(run_ids), ""),
        "commit_count": commit_count,
        "truncated_count": truncated_count,
        "non_json_count": non_json_count,
    }


def dot_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def dot_text(graph: dict[str, Any]) -> str:
    lines = [
        "digraph artifact_provenance {",
        "  rankdir=LR;",
        '  graph [fontname="Helvetica", labelloc=t, label="Artifact provenance"];',
        '  node [fontname="Helvetica", shape=box, style="rounded,filled"];',
        '  edge [color="#555555", fontname="Helvetica", arrowsize=0.7];',
    ]
    for artifact_id in sorted(graph["nodes"]):
        node = graph["nodes"][artifact_id]
        label_lines = [f"artifact {artifact_id}", node["artifact_dir"]]
        for key in ("operation", "flow_kind", "request_id"):
            if node[key]:
                label_lines.append(f"{key}: {node[key]}")
        label = "\n".join(label_lines)
        if node["missing"]:
            lines.append(
                f'  n{artifact_id} [label={dot_quote(label)}, '
                'fillcolor="#ffe6e6", style="rounded,dashed,filled"];'
            )
        else:
            fill = "#dff0d8" if artifact_id == 0 else "#ffffff"
            lines.append(
                f'  n{artifact_id} [label={dot_quote(label)}, '
                f'fillcolor="{fill}"];'
            )
    for (predecessor_id, artifact_id), count in sorted(graph["edges"].items()):
        attributes = f' [label="x{count}"]' if count > 1 else ""
        lines.append(f"  n{predecessor_id} -> n{artifact_id}{attributes};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_svg(dot: str, output: Path) -> None:
    if shutil.which("dot") is None:
        raise RuntimeError("SVG rendering requires Graphviz `dot` on PATH")
    completed = subprocess.run(
        ["dot", "-Tsvg", "-o", str(output)],
        input=dot,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "Graphviz rendering failed")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render Vecherinka artifact.commit JSONL events."
    )
    parser.add_argument("log", type=Path, help="structured JSONL log")
    parser.add_argument("--run-id", help="select one run from a combined log")
    parser.add_argument(
        "--dot-output", type=Path, help="DOT output; default: <log>.dot"
    )
    parser.add_argument("--svg-output", type=Path, help="optional SVG output")
    args = parser.parse_args()

    try:
        graph = load_graph(args.log, args.run_id)
        dot = dot_text(graph)
        dot_output = args.dot_output or args.log.with_suffix(".dot")
        dot_output.write_text(dot, encoding="utf-8")
        if args.svg_output:
            render_svg(dot, args.svg_output)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"artifact_graph: {error}", file=sys.stderr)
        return 2

    print(
        f"run_id={graph['run_id'] or '(unknown)'} "
        f"commits={graph['commit_count']} "
        f"nodes={len(graph['nodes'])} edges={sum(graph['edges'].values())} "
        f"dot={dot_output}"
    )
    if graph["truncated_count"]:
        print(
            f"warning: skipped {graph['truncated_count']} truncated artifact.commit event(s)",
            file=sys.stderr,
        )
    if graph["non_json_count"]:
        print(
            f"warning: skipped {graph['non_json_count']} non-JSON log line(s)",
            file=sys.stderr,
        )
    if args.svg_output:
        print(f"svg={args.svg_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
