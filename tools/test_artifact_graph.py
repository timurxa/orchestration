import json
from pathlib import Path
import tempfile
import unittest

from artifact_graph import dot_text, load_graph


class ArtifactGraphTests(unittest.TestCase):
    def test_reconstructs_edges_and_marks_missing_parent(self):
        records = [
            {
                "event": "artifact.commit",
                "run_id": "run-1",
                "fields": {
                    "artifact_id": 0,
                    "artifact_dir": "source",
                    "predecessor_ids": [],
                    "operation": "input",
                },
            },
            {
                "event": "artifact.commit",
                "run_id": "run-1",
                "fields": {
                    "artifact_id": 2,
                    "artifact_dir": "artifact-2",
                    "predecessor_ids": [0, 0, 9],
                    "operation": "join.fanout",
                    "flow_kind": "fk_fanout",
                },
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            path.write_text(
                "DIRECT_RESULT answer=ok\n"
                + "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )
            graph = load_graph(path)

        self.assertEqual(graph["commit_count"], 2)
        self.assertEqual(graph["non_json_count"], 1)
        self.assertEqual(graph["edges"][(0, 2)], 2)
        self.assertTrue(graph["nodes"][9]["missing"])
        rendered = dot_text(graph)
        self.assertIn('label="x2"', rendered)
        self.assertIn('fillcolor="#ffe6e6"', rendered)
        self.assertIn("operation: join.fanout", rendered)
        self.assertIn("flow_kind: fk_fanout", rendered)

    def test_rejects_mixed_runs_without_selection(self):
        records = [
            {"event": "artifact.commit", "run_id": "run-1", "fields": {"artifact_id": 0}},
            {"event": "artifact.commit", "run_id": "run-2", "fields": {"artifact_id": 0}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            path.write_text(
                "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                load_graph(path)


if __name__ == "__main__":
    unittest.main()
