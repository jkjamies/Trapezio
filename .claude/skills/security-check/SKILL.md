---
name: security-check
description: Security audit of current changes for iOS/Swift vulnerabilities and best practices
disable-model-invocation: true
argument-hint: "[--staged | --uncommitted]"
---

# Security Check

Perform a focused security audit on the current changes. Analyze the diff and the full content of changed files for security vulnerabilities, insecure patterns, and iOS-specific risks.

**Scope:** $ARGUMENTS

---

## Step 1: Gather Changes

Determine which changes to audit:
- `--staged` → `git diff --cached` (only staged changes)
- `--uncommitted` → `git diff HEAD` (only uncommitted changes)
- No flag → Default to `git diff main` (all changes on the branch vs main, committed and uncommitted)

Also run `git status` to identify new untracked files.

Read the diff output AND the full content of every changed file. Security issues often depend on context beyond the changed lines.

---

## Step 2: Secrets & Credentials

- [ ] No hardcoded API keys, tokens, passwords, or secrets
- [ ] No secrets in `Info.plist`, string literals, or configuration files committed to source
- [ ] No secrets logged or included in error messages
- [ ] No private keys or certificates committed
- [ ] `.gitignore` covers sensitive files (`.env`, `.netrc`, `*.p12`, `*.mobileprovision`)

---

## Step 3: Data Security

- [ ] Sensitive data not stored in plain `UserDefaults` (use Keychain instead)
- [ ] No sensitive data written to unprotected files without encryption
- [ ] No sensitive data in `Codable` objects passed via `TrapezioScreen` properties (they're serializable)
- [ ] SwiftData queries use parameterized predicates (no string interpolation in `#Predicate`)
- [ ] No sensitive data in `TrapezioState` structs that could be logged or exposed
- [ ] Keychain items use appropriate access control if applicable

---

## Step 4: Network Security

- [ ] No cleartext HTTP traffic (all URLs use HTTPS)
- [ ] No disabled certificate validation or custom `URLSessionDelegate` that accepts all certs
- [ ] No sensitive data in URL query parameters (use request body instead)
- [ ] API responses validated before use (no blind trust of server data)
- [ ] No `NSAppTransportSecurity` exceptions that weaken ATS
- [ ] No hardcoded URLs that should be configurable per environment

---

## Step 5: Input Validation

- [ ] User input validated before passing to use cases or repositories
- [ ] No predicate injection via `NSPredicate` or `#Predicate` with unsanitized user input
- [ ] Format strings don't use user-controlled data
- [ ] File paths not constructed from user input without sanitization
- [ ] Deep link / navigation parameters validated in routing. `TrapezioScreen` is `Codable`, and the library does **not** validate a decoded screen's parameters — anything decoded from a URL or other untrusted source must be checked before use

---

## Step 6: Concurrency Security

- [ ] No race conditions that could lead to auth bypass or privilege escalation
- [ ] Token/session state not shared mutably across isolation boundaries without synchronization
- [ ] `@unchecked Sendable` only used on interactor subclasses (not to suppress legitimate warnings)
- [ ] No `nonisolated(unsafe)` on shared mutable state. A multi-field struct is not read atomically, and any refcounted field races the writer — this is memory unsafety, not just a warning suppression
- [ ] Long-lived tasks are tracked in a `TrapezioTaskBag` so they cannot outlive their owner
- [ ] `AsyncStream` continuations are finished on `deinit`, and `onTermination` captures its registry weakly
- [ ] `OSAllocatedUnfairLock` usage is correct (balanced lock/unlock)
- [ ] Cancellation does not leave security-sensitive operations in an incomplete state

---

## Step 7: Logging & Error Handling

- [ ] No `print()` statements logging sensitive data (passwords, tokens, PII)
- [ ] No `debugPrint()` or `dump()` of sensitive objects
- [ ] Debug-only code guarded with `#if DEBUG`
- [ ] Error messages do not leak implementation details (class names, file paths). Note `StrataExecutionException` deliberately captures `underlyingErrorType` and `underlyingErrorDescription` for diagnostics — do not surface those to users
- [ ] `os.Logger` interpolations of route parameters or user data stay `.private` (the default for dynamic strings); no `print()` substituted for them
- [ ] `StrataException.message` doesn't contain internal system details exposed to users

---

## Step 8: Dependency Security

- [ ] No new external dependencies added without review
- [ ] `Package.swift` uses pinned or tested version ranges
- [ ] No known vulnerabilities in dependencies (currently: zero external deps)

---

## Step 9: Report

### Summary
Brief assessment of the security posture of the changes.

### Security Checklist
Show all completed checklists from Steps 2-8 with pass/fail/not-applicable indicators. Skip entire sections that are not applicable to the changed files.

### Vulnerabilities Found
List by severity:
- **Critical:** Exploitable vulnerabilities that must be fixed immediately
- **High:** Significant risks that should be fixed before merge
- **Medium:** Potential issues that should be addressed
- **Low:** Minor concerns or hardening opportunities

For each vulnerability:
- File path and line reference
- Description of the issue
- Recommended fix

### Clean
If no issues are found, state that the changes pass the security audit.
