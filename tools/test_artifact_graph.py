import sqlite3
from pathlib import Path
import tempfile
import unittest

from artifact_graph import dot_text, load_graph


class ArtifactGraphTests(unittest.TestCase):
    def test_joins_workflow_artifacts_attempts_and_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.sqlite3"
            with sqlite3.connect(path) as db:
                db.executescript("""
                    CREATE TABLE workflow_node(flow_key, kind, expansion_id, details_json);
                    CREATE TABLE workflow_edge(source_flow_key, edge_kind, position, target_flow_key);
                    CREATE TABLE artifact(artifact_id, operation, flow_kind, request_id);
                    CREATE TABLE predecessor(predecessor_id, artifact_id, position);
                    CREATE TABLE model_attempt(request_id, flow_key, input_artifact_id, output_artifact_id);
                    CREATE TABLE worker_session(session_id, request_id, generation, state, thread_id);
                    INSERT INTO workflow_node VALUES('answer', 'fk_model', 0, '{}');
                    INSERT INTO workflow_node VALUES('done', 'fk_pure', 0, '{}');
                    INSERT INTO workflow_edge VALUES('answer', 'continuation', 0, 'done');
                    INSERT INTO artifact VALUES(0, 'input', 'entry', '');
                    INSERT INTO artifact VALUES(1, 'model', 'fk_model', 'i:7');
                    INSERT INTO predecessor VALUES(0, 1, 0);
                    INSERT INTO model_attempt VALUES('i:7', 'answer', 0, 1);
                    INSERT INTO worker_session VALUES(3, 'i:7', 1, 'finished', 'thread-3');
                """)
            graph = load_graph(path)

        self.assertIn(("a:0", "w:answer", "input", "dashed"), graph["edges"])
        self.assertIn(("w:answer", "a:1", "output", "dashed"), graph["edges"])
        self.assertIn(("w:answer", "s:3", "worker", "dotted"), graph["edges"])
        self.assertIn(("a:0", "a:1", "predecessor", "solid"), graph["edges"])
        rendered = dot_text(graph)
        self.assertIn("thread-3", rendered)
        self.assertIn("\\n", rendered)
        self.assertNotIn("\\\\n", rendered)
        self.assertIn('"w:answer" -> "w:done"', rendered)


if __name__ == "__main__":
    unittest.main()
