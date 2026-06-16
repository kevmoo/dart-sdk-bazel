# Dart SDK (Bazel Fork)

This repository is an experimental fork of the official [Dart SDK](https://github.com/dart-lang/sdk) focused on migrating and maintaining a fully hermetic, modern [Bazel](https://bazel.build/) build graph alongside the upstream GN build system.

## 📌 Key Resources & Navigation

* **Upstream Dart SDK Readme**: See [`README.upstream.md`](README.upstream.md) for the official language overview, platform architecture, and licensing details.
* **Migration Guidelines & Status**: Architectural rules, historical progress, and roadmap docs live under [`docs/bazel-migration/`](docs/bazel-migration/).
* **Agent Worktree Automation**: Sandbox rules, isolated worktree helper scripts (`mkagenttree`, `rmagenttree`), and skills live under [`.agents/`](.agents/).

## 🚀 Getting Started

Initialize an isolated developer sandbox or AI agent worktree instantly using the automated setup helper:

```bash
~/.agents/scripts/mkagenttree bazel <task-name>
```

For standard local Bazel verification:

```bash
# Run fast analysis and formatting presubmits
./tools/bazel/presubmit.sh

# Build the standalone Dart VM runtime
bazel build //runtime/bin:dartvm
```

## ⚖️ License

Free and open source under the official Dart SDK license. See [`LICENSE`](LICENSE) and [`PATENT_GRANT`](PATENT_GRANT).
