# Contributing to EdgePad

Thank you for taking the time to contribute. EdgePad is open source, and pull requests are welcome for code, documentation, bug fixes, tests, and small usability improvements.

These guidelines help keep contributions easier to review and maintain.

## Table of Contents

- [Before You Start](#before-you-start)
- [Setting Up Your Environment](#setting-up-your-environment)
- [Making Changes](#making-changes)
- [Pull Requests](#pull-requests)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Project Boundaries](#project-boundaries)
- [Getting Help](#getting-help)

## Before You Start

- Search existing issues and pull requests before opening a new one.
- For small fixes, documentation improvements, tests, and clear bug fixes, feel free to open a pull request directly.
- For larger features or behavior changes, open an issue first so the approach can be discussed before you spend a lot of time implementing it.
- Keep changes focused. A pull request that fixes one problem is much easier to review than one that bundles several unrelated changes.

## Setting Up Your Environment

1. Fork the repository.
2. Clone your fork:

   ```bash
   git clone https://github.com/{your-username}/EdgePad.git
   cd EdgePad
   ```

3. Create a branch from `main`:

   ```bash
   git checkout -b feature/{short-description}
   ```

   Use a descriptive branch name, such as `feature/adjust-edge-preview` or `fix/volume-device-read`.

4. Build the app:

   ```bash
   ./build.sh
   ```

5. Run tests:

   ```bash
   swift test
   ```

## Making Changes

- Follow the existing Swift style in `Sources`.
- Prefer small, direct changes over broad refactors.
- Avoid new runtime dependencies unless there is a strong reason and the tradeoff is discussed first.
- Keep user-facing behavior grounded in the current app model: Auto, Media, and Reading modes.
- Add or update tests when changing pure logic, especially `EdgeDetector` behavior.
- For macOS permission-sensitive behavior, explain how you tested it and what hardware or macOS version you used.

## Pull Requests

1. Push your branch to your fork:

   ```bash
   git push origin feature/{short-description}
   ```

2. Open a pull request against `main`.
3. Include a clear description of:
   - What changed
   - Why it changed
   - How you tested it
   - Any related issue, such as `Fixes #123`
4. Include screenshots or screen recordings for visible UI changes.
5. Respond to review feedback. Maintainers may ask for changes before merging.

## Reporting Bugs

When reporting a bug, include:

- A clear title
- Steps to reproduce
- Expected behavior
- Actual behavior
- macOS version
- Mac model and trackpad type if relevant
- Console logs or screenshots when they help explain the issue

## Feature Requests

Feature requests are welcome. Please include:

- The problem you want to solve
- The behavior you expect
- Why the feature belongs in EdgePad
- Any risks, permissions, private API concerns, or compatibility notes you already know about

## Project Boundaries

The following changes are unlikely to be accepted:

- Telemetry, analytics, or tracking
- Network calls that are not clearly necessary
- Wrapped-web UI such as Electron, Tauri, or Catalyst
- Changes that require running as root
- Launch daemons or background services outside the app
- Large dependency additions without prior discussion
- Broad rewrites that make the private framework bindings harder to audit

## Getting Help

- Read [README.md](README.md) for build and usage instructions.
- Search existing GitHub issues for similar questions.
- Open a new issue if you need clarification before starting work.

Thanks for helping make EdgePad better.
