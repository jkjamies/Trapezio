---
name: fix
description: Diagnose and fix an error from a build failure, stack trace, or error message
disable-model-invocation: true
argument-hint: "<error message, stack trace, or description>"
---

# Fix

Diagnose and fix the provided error. This could be a build error, runtime crash, test failure, or a description of unexpected behavior.

**Input:** $ARGUMENTS

---

## Step 1: Parse the Error

Analyze the input to determine:
- **Error type:** Build error, runtime crash (stack trace), test failure, or described behavior
- **Location:** File path(s) and line number(s) referenced in the error
- **Root cause clues:** Error message, compiler error, exception type

If the input is a description rather than an error output, search the codebase for the relevant code.

---

## Step 2: Locate the Source

Read the file(s) referenced in the error. If no file is referenced:
- Search for relevant class/function names from the error message
- Check recent changes (`git diff main`) that may have introduced the issue

Read enough surrounding context to understand the code's intent — not just the failing line.

---

## Step 3: Diagnose

Identify the root cause. Common categories:

### Build Errors
- Missing imports or dependencies
- Type mismatches or incorrect generics
- Unresolved references (renamed/moved symbols)
- `Sendable` conformance violations
- `@MainActor` isolation mismatches
- Missing `Hashable`/`Codable` conformance on `TrapezioScreen`
- Missing `Equatable` conformance on `TrapezioState`

### Runtime Crashes
- Force unwrap on nil value
- `fatalError` in unoverridden `doWork(params:)` or `createObservable(params:)`
- Actor isolation violations
- Concurrency issues (data races)

### Test Failures
- Assertion mismatches (expected vs actual)
- Missing or incorrect Fakes
- Async timing (state not updated before assertion — missing `Task.sleep`)
- `AsyncStream.makeStream()` synchronization issues

### Logic Bugs
- Incorrect conditional or operator
- State not updated correctly via `update { }`
- Event not handled in `switch` block
- Navigation called with wrong screen/args
- Detached work reading `state` instead of taking a snapshot via `launch(snapshot:work:reduce:)`
- Observation started in `init` rather than `TrapezioLifecycle.onFirstAppear()`, so it is not scoped to the view

---

## Step 4: Fix

Apply the minimal fix that resolves the root cause. Do not refactor surrounding code or make unrelated improvements.

If the fix requires changes across multiple files (e.g., a renamed protocol), update all affected files.

---

## Step 5: Verify

After applying the fix:
- If it was a **build error:** Run `cd MESA && swift build` to verify it compiles
- If it was a **test failure:** Run `cd MESA && swift test --parallel` to verify it passes
- If it was a **Counter app error:** Run `xcodebuild build -scheme Counter -destination 'platform=iOS Simulator,name=iPhone 17'`
- If it was a **runtime crash or logic bug:** Verify the fix compiles and explain what changed

Report what was wrong and what was changed.
