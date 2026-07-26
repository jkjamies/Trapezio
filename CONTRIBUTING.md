# Contributing to MESA-iOS

## Getting set up

```bash
git clone https://github.com/jkjamies/MESA-iOS.git
cd MESA-iOS
git config core.hooksPath .githooks    # keeps the agent instruction mirrors in sync
```

## Verifying a change

| What | Command |
|:---|:---|
| Package build | `cd MESA && swift build` |
| Package tests | `cd MESA && swift test --parallel` |
| Sample app | `xcodebuild build -scheme Counter -destination 'platform=iOS Simulator,name=iPhone 17'` |
| Sample app tests | `xcodebuild test -scheme Counter -destination 'platform=iOS Simulator,name=iPhone 17'` |
| Agent docs in sync | `scripts/sync-agent-docs.sh --check` |

`swift test` compiles for macOS only. CI additionally builds every library for
`generic/platform=iOS` against the declared minimum, so a change that only breaks iOS will pass
locally and fail in CI. Build for iOS yourself if you touch anything platform-specific.

## Architecture rules

[`AGENTS.md`](AGENTS.md) is the full guide and the source of truth. In short:

- **Presentation** (`Trapezio`) is `@MainActor` and depends on Domain, never on Data.
- **Domain** (`Strata`) is actor-agnostic and depends on nothing.
- **Data** is background-isolated (`actor` / `ModelActor`).
- UI is a stateless function of State. The Store is the single source of truth.

Two rules that are easy to get wrong and expensive when you do:

- **Start long-lived work through the store's `launch` / `collect`,** not the free `strata*`
  functions. Only the store's methods are tracked in its `TrapezioTaskBag` and cancelled on
  deallocation. And capture `[weak self]` — a task holding its store strongly keeps the store
  alive and defeats the cancellation.
- **Build the whole dependency graph inside `TrapezioContainer`'s `makeStore` autoclosure.**
  Anything constructed in the surrounding factory body runs on every view evaluation and is
  discarded.

## Instruction files

`AGENTS.md` is canonical. `CLAUDE.md`, `GEMINI.md`, `.junie/guidelines.md`, and
`.github/copilot-instructions.md` are byte-identical copies. Edit `AGENTS.md`, then:

```bash
scripts/sync-agent-docs.sh
```

CI fails if they diverge; the pre-commit hook catches it first.

## Skills

Repository skills live in `.claude/skills/` and encode these conventions into scaffolding.
**When you change a public API, update the affected skills in the same PR.** A stale skill does
not merely mislead a reader — it writes the old API into new files.

## Pull requests

- One logical change per PR. Breaking changes need a `CHANGELOG.md` entry and a note in the
  README's migration section.
- New source files need the Apache 2.0 header (`2026`, or `2026-<currentYear>`).
- New behaviour needs tests. Library tests use Swift Testing; the sample app uses XCTest.
- Bump `VERSION` only when cutting a release — see the `bump-version` skill.
