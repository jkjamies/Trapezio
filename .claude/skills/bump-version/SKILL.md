---
name: bump-version
description: Bump library version in VERSION file and prepare release notes
disable-model-invocation: true
argument-hint: "<major|minor|patch>"
---

# Bump Version

Bump the MESA library version and prepare for release.

**Input:** $ARGUMENTS

---

## Step 1: Parse Input

Determine what to bump:
- `major` → increment major, reset minor and patch to 0
- `minor` → increment minor, reset patch to 0
- `patch` → increment patch

If no level is provided, ask the user which bump type they want.

---

## Step 2: Read Current Version

Read the `VERSION` file at the repository root to get the current version string.

---

## Step 3: Calculate New Version

Apply semantic versioning and display the version change for confirmation:

```text
Current → New
0.2.0   → 0.3.0
```

Ask the user to confirm before applying.

---

## Step 4: Apply Version Change

Update the `VERSION` file with the new version string.

Then update everything that quotes a version or is expected to move with a release:

- **`CHANGELOG.md`** — add a section for the new version at the top. Use the existing headings
  (`Breaking`, `Added`, `Fixed`, `Security`); omit any that do not apply. Breaking changes are
  mandatory to list, since this project is pre-1.0 and ships them in minor releases.
- **`Readme.md`** — the SPM install snippet (`from: "<version>"`). If this release is breaking,
  add or extend the **Migrating to X.Y.Z** section with the upgrade path for each change.
- **Skills** — if any public API changed in this release, verify the scaffolding skills
  (`add-screen`, `add-feature`, `add-interactor`, `add-tests`) and the review skills (`review`,
  `prepare-pr`, `security-check`, `fix`) generate and check against the *new* API. A stale skill
  writes the old API into new files.
- **`AGENTS.md`** — update if conventions changed, then run `scripts/sync-agent-docs.sh` to copy
  it over the four mirrors.

---

## Step 5: Generate Release Notes

Gather commits since the last release tag:
- Run `git log $(git describe --tags --abbrev=0)..HEAD --oneline` to get commits since the last tag

Generate release notes grouped by category:
- **Features** — new functionality
- **Improvements** — enhancements to existing features
- **Bug Fixes** — corrections
- **Internal** — refactoring, CI, docs

Format as markdown suitable for a GitHub release. Keep it consistent with the `CHANGELOG.md`
entry written in Step 4 — they should not tell different stories.

---

## Step 6: Summary

Report:
- Previous and new version
- Which files were updated alongside `VERSION`
- The expected release tag format: `v{VERSION}` (e.g., `v0.3.0`)
- The generated release notes
- Remind the user:
  1. Commit the `VERSION`, `CHANGELOG.md`, and README changes together
  2. Push to main — a draft release will be created automatically by `draft-release.yml`
  3. Review and publish the draft release on GitHub
  4. `publish-release.yml` validates the package and attaches the XCFrameworks on publish
