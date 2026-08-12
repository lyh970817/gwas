# GitHub configuration

Apply [`docs/coding-standards/ci-and-testing.md`](../docs/coding-standards/ci-and-testing.md) for CI and GitHub
policy. Workflow and action files own their exact commands, matrices, permissions, versions, pins, and guards;
inspect the live mechanism rather than copying remembered YAML.

Use the relevant pipeline or component PR skill for reviewer-facing preparation. Do not expose local paths,
private trackers, fixture overrides, or agent/development infrastructure in public artifacts.
