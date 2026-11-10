"""Exercise scheduling contracts from the checked-in Buildkite pipeline."""

from pathlib import Path
from types import SimpleNamespace
import unittest

import yaml

PIPELINE = Path(__file__).parents[1] / "pipeline.yml"


def selected_steps(branch, source, mr=None, fork=False):
    """Evaluate the pipeline's Buildkite conditions for one provider event."""
    repository = "https://code.eigin.ai/dev/eigin.git"
    build = SimpleNamespace(branch=branch, source=source,
                            pull_request=SimpleNamespace(id=str(mr) if mr is not None else None, repository="https://example.com/fork.git" if fork else repository))
    context = {"build": build, "pipeline": SimpleNamespace(repository=repository), "null": None}
    steps = yaml.safe_load(PIPELINE.read_text())["steps"]
    selected = {}
    for step in steps:
        condition = step.get("if", "True").replace("&&", " and ").replace("||", " or ")
        if eval(condition, {"__builtins__": {}}, context):
            selected[step["key"]] = step
    return selected


def ready(steps, passed):
    """Return eligible steps; conditionally excluded dependencies are skipped."""
    eligible = set()
    for key, step in steps.items():
        dependencies = step.get("depends_on", [])
        if isinstance(dependencies, str):
            dependencies = [dependencies]
        if key not in passed and (set(dependencies) & steps.keys()) <= passed:
            eligible.add(key)
    return eligible


class PipelineFlowTests(unittest.TestCase):
    def test_main_docs_complete_while_application_tests_wait(self):
        steps = selected_steps("main", "webhook")
        self.assertEqual(ready(steps, set()), {"versions", "ci-tests"})
        checks = {"versions", "ci-tests"}
        self.assertEqual(ready(steps, checks), {"docs-publish", "main-test-approval"})
        self.assertIn("input", steps["main-test-approval"])
        self.assertEqual(ready(steps, checks | {"docs-publish"}), {"main-test-approval"})
        self.assertEqual(ready(steps, checks | {"docs-publish", "main-test-approval"}),
                         {"linux-select", "ios-select"})

    def test_mr_runs_ios_automatically_after_checks(self):
        steps = selected_steps("feature/tests", "webhook", mr=12)
        self.assertEqual(ready(steps, set()), {"versions", "ci-tests", "linux-select", "cla"})
        self.assertFalse(any("input" in step or "block" in step for step in steps.values()))
        self.assertNotIn("ios-select", ready(steps, {"versions", "ci-tests"}))
        self.assertIn("ios-select", ready(steps, {"versions", "ci-tests", "cla"}))
        self.assertNotIn("docs-publish", steps)

    def test_forks_do_not_schedule_application_tests(self):
        steps = selected_steps("feature/tests", "webhook", mr=12, fork=True)
        self.assertEqual(set(steps), {"ci-tests"})

    def test_non_mr_branches_do_not_schedule_ios(self):
        for source in ("ui", "webhook", "schedule"):
            with self.subTest(source=source):
                steps = selected_steps("feature/tests", source)
                self.assertNotIn("ios-select", steps)
                self.assertNotIn("ios-tests", steps)


if __name__ == "__main__":
    unittest.main()
