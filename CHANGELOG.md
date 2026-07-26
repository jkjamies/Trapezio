# Changelog

All notable changes to MESA-iOS are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project is pre-1.0, so breaking
changes ship in minor releases.

## [0.3.0]

### Breaking

- **Minimum deployment target is now iOS 17 / macOS 14** (was iOS 16 / macOS 13), required for the
  Observation framework.
- **`TrapezioStore` is `@Observable`, not `ObservableObject`.** Drop `@StateObject` /
  `@ObservedObject` on stores; `TrapezioContainer` owns them. `objectWillChange` no longer exists —
  use `withObservationTracking`. `TrapezioMessageManager` changed the same way.
- **`TrapezioStore.state` is fully `@MainActor`-isolated.** `nonisolated(unsafe)` is gone. Detached
  work takes a snapshot via `launch(snapshot:work:reduce:)`.
- **`StrataException` refines `LocalizedError`.** Existing conformers need no changes.
- **`TrapezioInterop` is `@MainActor`,** matching `TrapezioNavigator`.
- **`goTo` ignores a screen already on top of the stack.**

See [Migrating to 0.3.0](Readme.md#-migrating-to-030) for the full upgrade path.

### Added

- `TrapezioTaskBag` — a cancellation scope owned by every store. Work started through the store's
  `launch` / `launchMain` / `collect` is cancelled when the store deallocates; completed tasks
  prune themselves.
- `TrapezioLifecycle` — optional `onFirstAppear()` / `onAppear()` / `onDisappear()` driven by
  `TrapezioRuntime`. Start observation in `onFirstAppear()`; consume navigation results in
  `onAppear()`.
- `TrapezioStore.launch(snapshot:work:reduce:)` for feeding current state into detached work.
- `AGENTS.md` as the canonical agent instructions, with `scripts/sync-agent-docs.sh` and a
  `.githooks/pre-commit` hook keeping the four mirrors honest.
- `SECURITY.md`, this changelog, and `CONTRIBUTING.md`.
- CI builds every library against the declared iOS minimum, and attaches XCFrameworks on release.

### Fixed

- **Data race on `TrapezioStore.state`.** A multi-field struct is not read atomically; any
  refcounted field raced the main actor's writes. The sample app triggered this on every
  concurrent tap.
- **Leaked tasks.** `strataCollect` opened detached tasks nothing ever cancelled, on streams that
  never finished. Each store instance leaked one per binding, for the lifetime of the process.
- **`StrataInteractor` races.** `inProgress` was locked but its stream continuation was not, and
  `inProgressStream` was a `lazy var` on an `@unchecked Sendable` class.
- **`inProgress` re-entrancy.** Concurrent executions on a shared interactor cleared the flag
  early; now refcounted.
- **`StrataSubjectInteractor.stream` split triggers between consumers** instead of broadcasting.
  All subscribers now receive every emission.
- **Streams never finished on deallocation,** parking consumers forever. Message, progress, and
  subject streams all finish now.
- **`StrataException.message` was lost** when a value was typed as `any Error` — Foundation's
  `localizedDescription` won the static lookup.
- **Sample app:** a fresh `ModelContext` per view evaluation, unbounded observer growth in the
  repository actor, `createObservable` called directly instead of `callAsFunction` + `.stream`,
  a hardcoded light-mode background, and `fatalError` on a failed SwiftData migration.
- **Documentation** claimed `strataRunCatching` re-throws `CancellationError` (it returns
  `.failure`), referenced a `StrataExecutionException.underlyingError` that does not exist, and
  omitted `StrataCancellationException`.
- **Repository skills** generated code against the pre-0.3.0 API; `security-check` listed
  `nonisolated(unsafe)` as an approved pattern.

### Security

- Release workflow passes `VERSION` and the release tag through the environment rather than
  interpolating them into shell bodies.
- Least-privilege `permissions:` and `persist-credentials: false` on all workflows.
- The sample's SwiftData store sets a `completeUnlessOpen` file-protection class.

## [0.2.0]

- Added the `TrapezioTest` library (`FakeTrapezioNavigator`, `TestEventSink`,
  `TrapezioStore.test()` / `.awaitState()`).
- Expanded navigation with typed result passing (`popWithResult`, `consumeResult`).
- Added cancellation handling to the Strata concurrency primitives.
- Added repository skills for scaffolding and review.

## [0.1.0]

- Initial release: `Trapezio`, `TrapezioNavigation`, and `Strata`.
