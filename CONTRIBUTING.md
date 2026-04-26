# A note on contributing

EdgePad is a personal project. The source is public under MIT so you can read it, learn from it, fork it, and build it yourself — but this isn't a community-maintained app and I'm not actively soliciting pull requests.

**What's welcome:**
- Bug reports via [GitHub issues](https://github.com/thomaslenh/EdgePad/issues), with reproduction steps
- Security issues — please use GitHub's private vulnerability reporting, don't open a public issue
- Forks, for your own use

**What to do before opening a PR:**
- Open an issue first and ask. Drive-by PRs (new features, refactors, style changes, dependency additions) will most likely be closed unsolicited. I'd rather you spend the time on something that has a chance of merging.

**What I won't merge regardless:**
- Network / telemetry / analytics code
- New runtime dependencies
- Wrapped-web UI (Electron, Tauri, Catalyst)
- Anything that requires running as root or installing a launchd daemon

If you're forking for your own use, the code style is documented in [CLAUDE.md](CLAUDE.md) and the architecture in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Have at it.
