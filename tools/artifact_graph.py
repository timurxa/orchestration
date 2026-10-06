#!/usr/bin/env python3
"""Render a Vecherinka SQLite run graph as DOT or SVG."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
from typing import Any


def load_graph(path: Path) -> dict[str, Any]:
    nodes: dict[str, dict[str, str]] = {}
    edges: list[tuple[str, str, str, str]] = []
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        for row in db.execute(
            "SELECT flow_key, kind, expansion_id, details_json FROM workflow_node "
            "ORDER BY expansion_id, flow_key"
        ):
            key = "w:" + row["flow_key"]
            details = json.loads(row["details_json"])
            nodes[key] = {
                "label": f"{row['flow_key']}\n{row['kind']}"
                + (f"\n{details}" if details else ""),
                "group": "workflow",
            }
        for row in db.execute(
            "SELECT source_flow_key, edge_kind, position, target_flow_key "
            "FROM workflow_edge ORDER BY source_flow_key, edge_kind, position"
        ):
            edges.append(("w:" + row["source_flow_key"],
                          "w:" + row["target_flow_key"],
                          row["edge_kind"], "solid"))
        for row in db.execute(
            "SELECT artifact_id, operation, flow_kind, request_id FROM artifact "
            "ORDER BY artifact_id"
        ):
            key = f"a:{row['artifact_id']}"
            nodes[key] = {
                "label": f"artifact {row['artifact_id']}\n{row['operation']}"
                + (f"\n{row['flow_kind']}" if row["flow_kind"] else ""),
                "group": "artifact",
            }
        for row in db.execute(
            "SELECT predecessor_id, artifact_id FROM predecessor "
            "ORDER BY artifact_id, position"
        ):
            edges.append((f"a:{row['predecessor_id']}", f"a:{row['artifact_id']}",
                          "predecessor", "solid"))
        for row in db.execute(
            "SELECT request_id, flow_key, input_artifact_id, output_artifact_id "
            "FROM model_attempt ORDER BY request_id"
        ):
            flow = "w:" + row["flow_key"]
            if flow in nodes and row["input_artifact_id"] is not None:
                edges.append((f"a:{row['input_artifact_id']}", flow, "input", "dashed"))
            if flow in nodes and row["output_artifact_id"] is not None:
                edges.append((flow, f"a:{row['output_artifact_id']}", "output", "dashed"))
        for row in db.execute(
            "SELECT session_id, request_id, generation, state, thread_id "
            "FROM worker_session ORDER BY session_id"
        ):
            key = f"s:{row['session_id']}"
            nodes[key] = {
                "label": f"worker {row['session_id']} (gen {row['generation']})\n"
                f"{row['state']}\n{row['thread_id']}",
                "group": "worker",
            }
            attempt = db.execute(
                "SELECT flow_key FROM model_attempt WHERE request_id = ?",
                (row["request_id"],),
            ).fetchone()
            if attempt and "w:" + attempt["flow_key"] in nodes:
                edges.append(("w:" + attempt["flow_key"], key, "worker", "dotted"))
    return {"nodes": nodes, "edges": edges}


def dot_quote(value: str) -> str:
    return ('"' + value.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n") + '"')


def dot_text(graph: dict[str, Any]) -> str:
    lines = [
        "digraph vecherinka {", "  rankdir=LR;",
        '  graph [fontname="Helvetica", labelloc=t, label="Vecherinka run"];',
        '  node [fontname="Helvetica", shape=box, style="rounded,filled"];',
    ]
    for key, node in sorted(graph["nodes"].items()):
        color = {"workflow": "#e8f0fe", "artifact": "#ffffff", "worker": "#fff2cc"}[node["group"]]
        lines.append(f"  {dot_quote(key)} [label={dot_quote(node['label'])}, fillcolor={dot_quote(color)}];")
    for source, target, label, style in graph["edges"]:
        lines.append(f"  {dot_quote(source)} -> {dot_quote(target)} [label={dot_quote(label)}, style={dot_quote(style)}];")
    return "\n".join(lines + ["}", ""])


def render_svg(dot: str, output: Path) -> None:
    if shutil.which("dot") is None:
        raise RuntimeError("SVG rendering requires Graphviz `dot` on PATH")
    completed = subprocess.run(["dot", "-Tsvg", "-o", str(output)], input=dot,
                               text=True, capture_output=True, check=False)
    if completed.returncode:
        raise RuntimeError(completed.stderr.strip() or "Graphviz rendering failed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, help="Vecherinka SQLite database")
    parser.add_argument("--dot-output", type=Path)
    parser.add_argument("--svg-output", type=Path)
    args = parser.parse_args()
    try:
        graph = load_graph(args.database)
        dot = dot_text(graph)
        output = args.dot_output or args.database.with_suffix(".dot")
        output.write_text(dot, encoding="utf-8")
        if args.svg_output:
            render_svg(dot, args.svg_output)
    except (OSError, ValueError, sqlite3.Error, RuntimeError) as error:
        print(f"artifact_graph: {error}", file=sys.stderr)
        return 2
    print(f"nodes={len(graph['nodes'])} edges={len(graph['edges'])} dot={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
