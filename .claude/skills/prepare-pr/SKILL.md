---
name: prepare-pr
description: Thorough pre-merge audit — dependency graph, correctness, conventions, security, test coverage, and improvement suggestions
disable-model-invocation: true
argument-hint: ""
---

# Prepare PR

Perform a thorough pre-merge audit of the current changes. Start from the diff, then follow the dependency graph to understand how the changes fit into the broader system. Check correctness, security, MESA conventions, test coverage, and suggest improvements.

**Scope:** $ARGUMENTS

---

## Step 1: Gather Changes

Get all changes on the branch compared to main:

1. Run these commands in parallel:
   - `git log main..HEAD --oneline` — list commits on this branch
   - `git diff main...HEAD --stat` — file-level summary of changes
2. Then run `git diff main...HEAD` to get the full diff.
   - If the diff output is too large to read at once, read it in chunks using offset/limit, or read each changed file individually instead.
3. Run `git status` to identify any uncommitted or untracked changes not yet in the diff.

Read the diff output AND the full content of every changed file.

**Do NOT use `gh` CLI commands** — it may not be installed. Use only `git` commands for gathering diffs and commit history.

---

## Step 2: Follow the Dependency Graph

Starting from the changed files, trace connections to understand the full impact:

- Read related files within the same feature (State, Event, Screen, Store, UI, Factory, interactors)
- Read interfaces being implemented or extended
- Read consumers of changed APIs — if a public protocol, use case, or domain type was modified, find the files that depend on it and check they are compatible
- Read Factory files to verify dependency assembly is correct

The goal is to understand how the changes integrate with everything that touches them — not to review the entire codebase, but to verify nothing is broken or inconsistent at the boundaries.

---

## Step 3: Correctness & Logic Review

Present findings with checkboxes as you go:

### Logic & Correctness
- [ ] No broken logic (incorrect conditionals, wrong operator, inverted checks)
- [ ] No off-by-one errors or boundary issues
- [ ] No race conditions or concurrency issues
- [ ] No force unwraps (`!`) without justification
- [ ] No unreachable code or dead branches
- [ ] Error paths handled correctly (not swallowed silently)
- [ ] State mutations are correct and complete (no partial updates that leave inconsistent state)
- [ ] Event handling covers all enum cases (no missing `switch` branches)
- [ ] Changed APIs are compatible with all consumers found in Step 2

### Best Practices
- [ ] No unnecessary allocations in SwiftUI recomposition paths
- [ ] `@MainActor` isolation used correctly on Stores
- [ ] Actor isolation used correctly on data layer
- [ ] No blocking calls on the main thread
- [ ] Resources cleaned up (no leaked tasks or streams)

### Security
- [ ] No hardcoded API keys, tokens, passwords, or secrets
- [ ] No secrets logged or included in error messages
- [ ] No sensitive data in `TrapezioScreen` properties (they're `Codable` and could be serialized)
- [ ] Input from external sources validated at system boundaries

For a deeper security audit, run `/security-check`.

### General Quality
- [ ] No TODO/FIXME left unaddressed without tracking
- [ ] No unused imports or dead code introduced
- [ ] Naming is clear and consistent

---

## Step 4: Convention Review

Present findings with checkboxes as you go:

### MESA / Trapezio Conventions
- [ ] **UDF flow respected:** UI → Event → Store → State → UI
- [ ] **Stateless UI:** `TrapezioUI.map()` holds no business logic or mutable state
- [ ] **Store pattern:** `@MainActor final class` extending `TrapezioStore<Screen, State, Event>`
- [ ] **State immutability:** Mutations only via `update { $0.field = value }`
- [ ] **Dependencies injected:** Via `init`, not globals or singletons
- [ ] **Factory pattern:** `TrapezioContainer(makeStore:ui:)` wrapping, with the whole dependency graph built **inside** the autoclosure
- [ ] **Lifecycle:** observation started in `TrapezioLifecycle.onFirstAppear()`, navigation results consumed in `onAppear()` — not in `init`
- [ ] **Navigation:** `TrapezioNavigator` used correctly; screen registered in `ContentView` builder
- [ ] **Messages:** Transient UI messages use `TrapezioMessageManager`

### Strata Conventions
- [ ] Interactors return `StrataResult`, not raw exceptions
- [ ] `StrataInteractor` overrides `doWork(params:)`, calls via `execute(params:)`
- [ ] `StrataSubjectInteractor` overrides `createObservable(params:)`; consumers trigger via `callAsFunction(_:)` and read `.stream`, never calling `createObservable` directly
- [ ] Stores use their own `launch`/`collect` for async work — not raw `Task { }`, and not the untracked free `strata*` functions
- [ ] Detached work never reads `state` directly; `launch(snapshot:work:reduce:)` used where the work depends on current state
- [ ] `StrataResult` extensions used idiomatically (`onSuccess`, `onFailure`, `fold`, `map`, `flatMap`, `recover`, etc.)
- [ ] Loading state bound via `collect(useCase.inProgressStream)`

### Clean Architecture
- [ ] Domain layer has no framework imports (no SwiftUI, SwiftData, UIKit — only `Foundation` and `Strata`)
- [ ] Data layer uses `actor`/`ModelActor` isolation
- [ ] Presentation depends on Domain, never on Data directly
- [ ] Repository is a protocol in Domain, implemented in Data
- [ ] Feature isolation maintained — no cross-feature presentation imports

### License
- [ ] All new source files have the Apache 2.0 license header with correct year

---

## Step 5: Test Coverage Analysis

- [ ] `{Name}Store.swift` has `{Name}StoreTests.swift`
- [ ] `{Name}UseCase.swift` has `{Name}UseCaseTests.swift`
- [ ] All events and state transitions in changed code are covered
- [ ] Error paths and edge cases are tested
- [ ] Navigation flows are tested (nil navigator doesn't crash)
- [ ] Fakes exist for new dependencies in `Fakes/` subdirectory or use `TrapezioTest` library (`FakeTrapezioNavigator`, `TestEventSink`)
- [ ] Async tests use `Task.sleep`, or `awaitState`, for detached `launch` timing; `awaitState`'s `Bool` result is asserted
- [ ] Store tests are `@MainActor`
- [ ] Test doubles marked `@unchecked Sendable` where needed

Flag any gaps.

---

## Step 6: Improvement Suggestions

Beyond issues, suggest improvements that are directly relevant to the changed code:
- Code simplification opportunities
- Better use of MESA/Strata patterns
- Performance considerations
- Accessibility (`accessibilityIdentifier` on testable elements)
- Better error handling or user feedback

---

## Step 7: Report

Present a structured report:

### Summary
Brief overview of the changes and overall assessment (ready to merge, needs work, etc.).

### Checklist Results
Show all completed checklists from Steps 3-5 with pass/fail/not-applicable indicators.

### Blocking Issues
Must fix before merge. Include file path and line references.

### Warnings
Should fix. Style issues, potential problems, missing patterns.

### Missing Tests
For each file missing tests or test cases:
- File path
- What specific tests are needed
- Suggest running `/add-tests @<filepath>` to generate them

### Suggestions
Improvement opportunities. These are optional but recommended.
