# Contributing to EdgePad

Thanks for wanting to help. EdgePad is small and opinionated — please read this before opening a large PR.

## Before opening a PR

1. **Open an issue first** if the change is bigger than a typo or a bug fix. Getting alignment saves everyone time.
2. **Read [docs/PRD.md](docs/PRD.md)** to understand the product scope.
3. **Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** to understand the code structure.
4. **Check [docs/ROADMAP.md](docs/ROADMAP.md)** — the feature might already be planned.

## Development setup

```bash
git clone https://github.com/thomaslenh/EdgePad.git
cd EdgePad
./build.sh run
```

## Code style

- Swift 6, strict concurrency on
- `@MainActor` on anything touching UI
- Value types by default
- `final class` for reference types
- Doc comments (`///`) on public APIs
- `os_log` for logging, never `print`
- Match the existing file structure

## Commit messages

Conventional commits:

```
feat: add bottom-edge horizontal scroll
fix: clamp volume to [0,1] when sensitivity > 1
docs: update PRD with auto-profile section
chore: bump OpenMultitouchSupport to 3.0.4
refactor: extract scroll logic into ScrollController
test: add EdgeDetector dead-zone tests
```

## PR checklist

- [ ] Builds clean (`swift build -c release`)
- [ ] Tests pass (`swift test`)
- [ ] `build.sh` produces a working .app
- [ ] New public APIs have doc comments
- [ ] If you added an edge action, updated `AppDelegate`, `EdgeProfile`, `OverlayWindow` HUD, and docs
- [ ] No `print(...)` statements added
- [ ] No network calls added
- [ ] Changelog entry in the PR description

## What kinds of changes we're looking for

**Easy wins** (small PRs, low risk):
- Tuning defaults (dead zone, sensitivity, edge inset)
- Bug fixes with reproducible steps
- Doc improvements
- New test cases for `EdgeDetector`
- HUD polish for dark/light mode / high contrast
- Localization (String Catalogs)

**Medium** (discuss first):
- New edge actions
- New profiles beyond Media and Reading
- Settings UI additions
- Haptic feedback integration

**Large** (please open an issue, maybe ADR):
- Auto profile switching
- MIDI output mode
- Plugin system
- Xcode project / DMG / Sparkle integration
- Architecture changes

## What we won't accept

- Network / telemetry / analytics code without explicit opt-in flag
- Dependencies that pull in Foundation-replacement libraries
- `Electron`, `Tauri`, `Catalyst`, or any wrapped-web UI
- Closed-source binary blobs
- Cryptocurrency / wallet / ad-network integrations
- Anything that requires running as root or a launchd daemon

## Security

If you find a security issue, **do not open a public issue**. Email the maintainer directly or use GitHub's private vulnerability reporting.

## License

By contributing, you agree your contributions are MIT licensed.

---

See also: [docs/PRD.md](docs/PRD.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/ROADMAP.md](docs/ROADMAP.md)
