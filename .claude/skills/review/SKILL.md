---
name: review
description: Quick review of the current diff for bugs, logic errors, convention violations, and test gaps
disable-model-invocation: true
argument-hint: "[--staged | --uncommitted]"
---

# Review Changes

Quick feedback on the current diff. Focus on catching bugs, logic errors, and convention violations. Keep output concise — this is a development pulse check, not a pre-merge audit.

**Scope:** $ARGUMENTS

---

## Step 1: Gather the Diff

Determine which diff to review:
- `--staged` → `git diff --cached` (only staged changes)
- `--uncommitted` → `git diff HEAD` (only uncommitted changes)
- No flag → Default to reviewing the current branch against `main`

**When reviewing the current branch against main (default):**

1. Run these commands in parallel:
   - `git log main..HEAD --oneline` — list commits on this branch
   - `git diff main...HEAD --stat` — file-level summary of changes
2. Then run `git diff main...HEAD` to get the full diff.
   - If the diff output is too large to read at once, read it in chunks using offset/limit, or read each changed file individually instead.
3. Run `git status` to identify any uncommitted or untracked changes not yet in the diff.

**Do NOT use `gh` CLI commands** — it may not be installed. Use only `git` commands for gathering diffs and commit history.

Read the diff output AND the full content of each changed file so you can assess whether the changed code is correct in context.

---

## Step 2: Scan for Issues

Read each changed file and look for actual problems. Do NOT present an exhaustive checklist — only report issues you find. Look for:

- Broken logic (incorrect conditionals, wrong operator, inverted checks)
- Race conditions or concurrency issues
- Force unwraps (`!`) without justification
- Unreachable code or dead branches
- Swallowed errors
- Incomplete state mutations
- Missing `case` branches for event enums
- Raw `Task { }`, or the free `strata*` functions, instead of the store's `launch`/`collect` (only the store's methods are cancelled on deallocation)
- Detached work reading `state` directly instead of using `launch(snapshot:work:reduce:)`
- `@State` or other mutable storage in `TrapezioUI` structs
- Retain cycles in `collect`/`launch` closures (missing `[weak self]`) — a task capturing its store strongly keeps the store alive and defeats automatic cancellation
- Observation started in `init` instead of `TrapezioLifecycle.onFirstAppear()`
- Blocking calls on the main thread
- Leaked tasks or streams

If no issues are found, say so briefly.

---

## Step 3: Convention Check

Verify MESA conventions are followed. Present as a concise pass/fail list — only include items relevant to the changed code:

- [ ] UDF flow: UI → Event → Store → State → UI
- [ ] Stateless UI: `TrapezioUI.map()` holds no business logic or mutable state
- [ ] Store is `@MainActor final class` extending `TrapezioStore`
- [ ] State mutations only via `update { $0.field = value }`
- [ ] Dependencies injected via `init`, not globals or singletons
- [ ] Async work uses the store's `launch`/`collect`, not raw `Task { }` or untracked `strata*` calls
- [ ] Interactors return `StrataResult` (or use `executeCatching`, which never throws — `CancellationError` becomes `.failure(StrataCancellationException)`)
- [ ] Domain layer has no framework imports (no SwiftUI, SwiftData)
- [ ] Data layer uses `actor` isolation
- [ ] Module boundaries respected (presentation doesn't import data layer)
- [ ] New source files have Apache 2.0 license header

Skip items that don't apply to the changed files.

---

## Step 4: Test Gaps

For each changed or new source file, briefly note missing or incomplete test coverage. Keep it to one or two lines per gap — just identify what's missing:

- Missing test files (e.g., "No unit test for `ProfileStore`")
- Uncovered new behavior (e.g., "New `delete` event not tested in `ProfileStoreTests`")
- Missing fakes for new dependencies

Do not suggest running other skills or provide detailed instructions on how to write the tests.

---

## Step 5: Report

Keep the report compact:

### Summary
One or two sentences on what changed and overall quality.

### Issues
List problems found in Step 2, grouped by severity:
- **Blocking:** Must fix (bugs, broken logic, broken conventions)
- **Warning:** Should fix (potential problems, best practice violations)

If none, say "No issues found."

### Conventions
Show the pass/fail list from Step 3. Omit items marked N/A.

### Test Gaps
List gaps from Step 4. If coverage looks complete, say so.
