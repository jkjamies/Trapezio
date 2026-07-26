# MESA-iOS Architecture Review

Review of the full repository at `1b3bd12` — `MESA/Sources/*`, `MESA/Tests/*`, the `Counter` sample
app, CI workflows, and documentation.

**Verification note:** no Swift toolchain was available in the review environment, so nothing here was
compiled or executed. Every finding below was derived by reading the source. Findings are labelled
**Confirmed** (follows directly from the code and documented Swift semantics) or **Likely** (needs a
build/run to settle).

## Status

Everything below except deep links has been addressed on this branch. Deep-link and state
restoration (**S2-7**) is deferred by request — the `Codable` requirement on `TrapezioScreen`
stays in place for it.

| Finding | Status |
|:---|:---|
| S1-1 · `state` data race | Fixed — `nonisolated(unsafe)` removed, `launch(snapshot:)` added |
| S1-2 · unsynchronised continuation | Fixed — held under the same lock as the flag |
| S1-3 · `lazy var` stream | Fixed — built eagerly in `init` |
| S1-4 · uncancelled collect tasks | Fixed — `TrapezioTaskBag` + store-scoped `launch`/`collect` |
| S1-5 · repository observer growth | Fixed — pruned on yield |
| S1-6 · `ModelContext` per render | Fixed — graph moved inside the autoclosure |
| S1-7 · message continuations never finished | Fixed — `ContinuationRegistry` finishes on dealloc |
| S2-1 · subject stream single-consumer | Fixed — broadcast from one driver task |
| S2-2 · sample bypasses the interactor | Fixed — `callAsFunction` + `.stream` |
| S2-3 · no cancellation on teardown | Fixed — see S1-4 |
| S2-4 · soft timeout | Documented precisely; behaviour unchanged |
| S2-5 · `inProgress` re-entrancy | Fixed — refcounted |
| S2-6 · duplicate push | Fixed — top-of-stack guard |
| S2-7 · `Codable` funds nothing | **Deferred** — deep links to be implemented later |
| S2-8 · no lifecycle events | Fixed — `TrapezioLifecycle` driven by the runtime |
| S2-9 · `localizedDescription` shadowing | Fixed — `StrataException: LocalizedError` |
| S2-10 · container erases store type | Documented — primary initializer preserves it |
| S2-11 · `TrapezioInterop` unisolated | Fixed — `@MainActor`, matching the navigator |
| S3-1 … S3-8 · doc drift | Fixed; instruction files single-sourced with a CI check |
| S4-1 … S4-3 · workflow hardening | Fixed |
| S4-5, S4-6 · SwiftData template | Fixed — protection class set, in-memory fallback |
| S4-7 · no `SECURITY.md` | Fixed |
| S4-8 · no DI story | **Open** — pairs with the deep-link registry |
| S4-9 · no SwiftUI-layer tests | Partly fixed — the testable logic is covered; host-level tests still open |
| S4-10, S4-11 · weak test assertions | Fixed |
| S4-12 · repo furniture | Fixed — CHANGELOG, CONTRIBUTING, pinned language mode, sync script + hook |
| Sample-app polish | Fixed |
| S3-9 · skills generate against the old API | Fixed — all nine updated (missed in the original pass) |

Closed after the first pass, in **0.3.0**: S2-11 (`TrapezioInterop` is now `@MainActor`),
S4-5 and S4-6 (the sample's store sets a file-protection class and degrades to in-memory
instead of calling `fatalError`).

Also in 0.3.0, beyond the review: the deployment floor moved to iOS 17 / macOS 14 and the
observation layer moved to `@Observable`. That was listed in the review only as a note under
S3-8; it landed as a deliberate release decision. It removes the manual `objectWillChange.send()`
and gives property-granular invalidation, and it makes reading `state` off the main actor a
compile error rather than a documented rule.

**S3-9, missed in the original pass.** The review covered `MESA/`, `Counter/`, CI, and the four
instruction files, but never opened `.claude/skills/`. Those nine skills are what actually
generate new code in this repo, and every scaffolding one emitted the pre-0.3.0 API —
`setupBindings()` from `init`, untracked `strataCollect`, dependencies hoisted out of the
`TrapezioContainer` autoclosure, a non-isolated `FakeInterop`. `security-check` went further and
listed `nonisolated(unsafe)` on `TrapezioStore.state` as an *approved* framework pattern, and
`review` asserted that `executeCatching` throws, which was never true. A stale skill is worse than
stale prose: it writes the old API into new files. All nine are updated, and the instructions now
say to update them in the same change as any library API change.

Also fixed here: `AGENTS.md` did not exist. It is now the canonical instructions file, with the
four tool-specific files as byte-identical copies and the CI sync job comparing against it.

**S4-9, partially.** The SwiftUI layer cannot be exercised without a hosted view, but the logic
worth protecting can. `TrapezioStoreBox` — the resolve-once guarantee that replaced
`@StateObject`'s autoclosure and is all that stands between an adopter and a rebuilt dependency
graph per render — is now `internal` and directly tested. So are `TrapezioAnyScreen`'s identity
semantics and `TrapezioLifecycle`'s defaults. What remains untested is SwiftUI's *retention* of
the box across view updates, which genuinely needs a host.

**S4-12.** `CHANGELOG.md`, `CONTRIBUTING.md`, `scripts/sync-agent-docs.sh` with a
`.githooks/pre-commit` hook (CI runs the same script, so local and CI cannot disagree), and
`swiftLanguageMode(.v6)` pinned per target rather than inherited from the tools version. Platform
support was **not** widened to watchOS/tvOS/visionOS — that would advertise support nothing
verifies.

Still open: S2-7 + S4-8 (deep links and the factory registry — one piece of work, deferred by
request), and host-level tests for `TrapezioContainer` / `TrapezioNavigationHost`.

> **Nothing on this branch has been compiled.** The review environment has no Swift toolchain, so
> CI is the first real build. Highest-risk items, in order: the `@Observable` migration (macro
> behaviour on a generic `open` class, and `TrapezioContainer`'s lazy store box replacing
> `@StateObject`'s autoclosure), the XCFramework job in `publish-release.yml` (unverifiable
> `xcodebuild` archive paths), and the strict-concurrency annotations on the task bag and
> registries.

---

Severity legend:

| | Meaning |
|:---|:---|
| **S1** | Memory-unsafe, leaks unboundedly, or silently corrupts behaviour in normal use |
| **S2** | Real bug or design hole that will bite an adopter |
| **S3** | Documentation that contradicts the code, or an unfulfilled promise |
| **S4** | Polish, hygiene, hardening |

---

## Executive summary

The bones are good: the layering rules are clear, `StrataResult` is a well-rounded Kotlin-style
result type, the navigator/result-passing surface is thoughtfully specified, and test coverage of the
pure logic (`StrataResult`, navigator, message queue) is genuinely solid.

What stops it being an out-of-the-box architecture today is **lifecycle**. `TrapezioStore` has no
teardown story. Every concurrency primitive returns a `Task` "for cancellation", but nothing in the
framework ever cancels one, there is no task bag, no `deinit` hook, and no appear/disappear events.
The sample app demonstrates the consequence directly: navigating to Summary and back leaks two
detached tasks, one SwiftData `ModelContext`, and one permanent observer registration inside the
repository actor — every single time.

Sitting underneath that are three memory-safety problems: `TrapezioStore.state` is
`nonisolated(unsafe)` and is genuinely read off-main by the shipped sample; `StrataInteractor` guards
`inProgress` with a lock but leaves the adjacent continuation and a `lazy var` completely
unsynchronised on an `@unchecked Sendable` class.

And a cluster of documentation claims are contradicted by the code — most sharply, both README and
`CLAUDE.md` state that `strataRunCatching` re-throws `CancellationError`, which is the opposite of
what it does.

Counts: **7 × S1**, **11 × S2**, **9 × S3**, **12 × S4**. (S3-9 was added after the
first pass — see Status.)

---

## S1 — Memory safety and unbounded growth

### S1-1 · `TrapezioStore.state` is a real data race, and the sample triggers it — Confirmed

`MESA/Sources/Trapezio/TrapezioStore.swift:45`

```swift
nonisolated(unsafe) public private(set) var state: State
```

The doc comment justifies this as "Readable from any isolation context (value-type copy)". Being a
value type is not sufficient. A struct with more than one stored property is not read atomically, and
any field that is refcounted (`String`, `Array`, `Optional<T>` where `T` is non-trivial, a class
reference) has its retain/release raced during a concurrent read/write. The result is a torn read at
best and heap corruption at worst.

This is not theoretical here. `Counter/Counter/Counter/CounterStore.swift:66`:

```swift
case .divideByTwo:
    strataLaunch(
        work: { await self.divideUsecase.execute(value: self.state.count) },
```

`work` runs in `Task.detached`. It reads `self.state` off the main thread. `CounterState` holds
`message: TrapezioMessage?`, which holds a `String` — non-trivial. A user tapping `+` while `÷2` is
in flight races a main-actor write against a detached read.

`Counter/Counter/Summary/SummaryStore.swift:62` has the identical pattern with `self.state.value`.

Note that `CLAUDE.md` and the `strataLaunch` doc comment both already prescribe the correct
idiom — hoist the value on the main actor first (`let count = state.count`) — and the sample ignores
it. That mismatch is itself the tell: if the framework's own sample can't follow the rule, adopters
won't either.

**Fix.** Make the unsafe read impossible rather than merely discouraged:

1. Drop `nonisolated(unsafe)`; let `state` be plain `@MainActor`-isolated.
2. Give `work` the state it needs by value. Add an overload that snapshots on the main actor before
   detaching:

   ```swift
   public func launch<V: Sendable, T: Sendable>(
       snapshot: @MainActor (State) -> V,
       work: @escaping @Sendable (V) async -> T,
       reduce: @escaping @MainActor @Sendable (T) -> Void
   ) -> Task<Void, Never>
   ```

3. If cross-isolation reads must stay for migration, keep the storage behind
   `OSAllocatedUnfairLock<State>` so reads are at least atomic, and rename the property to make the
   snapshot semantics explicit.

Option 1 + 2 is the right call for a framework that markets strict UDF.

---

### S1-2 · `StrataInteractor.inProgressContinuation` is unsynchronised — Confirmed

`MESA/Sources/Strata/StrataInteractor.swift:39-63`

```swift
private var inProgressContinuation: AsyncStream<Bool>.Continuation?   // no lock

private func setInProgress(_ value: Bool) {
    _inProgress.withLock { $0 = value }        // locked
    inProgressContinuation?.yield(value)       // unlocked read
}
```

The `Bool` is carefully protected; the continuation next to it is not. The class is
`@unchecked Sendable`, so the compiler is silent. Writers:

- the `AsyncStream` build closure (`self?.inProgressContinuation = continuation`, line 51)
- `onTermination` (`self?.inProgressContinuation = nil`, line 55) — `@Sendable`, fires on an
  arbitrary thread when the consumer stops iterating

Readers: `setInProgress`, from whatever thread `execute` happens to run on.

A consumer abandoning `inProgressStream` while an `execute` is in flight is exactly the
teardown-under-load case, and it races an Optional-of-struct write against a read.

**Fix.** Hold the continuation in the same `OSAllocatedUnfairLock` as the flag, so a single
`withLock` both updates the value and captures the continuation to yield to (yield *outside* the
lock to avoid re-entrancy).

---

### S1-3 · `inProgressStream` is a `lazy var` on a concurrently-accessed class — Confirmed

`MESA/Sources/Strata/StrataInteractor.swift:49`

```swift
public private(set) lazy var inProgressStream: AsyncStream<Bool> = { ... }()
```

`lazy` initialisation is not atomic. Two threads racing the first access both run the initialiser;
one `AsyncStream` is discarded and `inProgressContinuation` is left pointing at whichever closure ran
last. The winning consumer then holds a stream whose continuation was overwritten and receives
nothing.

Given the documented use — a store binds it in `init` — a same-instance race is unlikely in the
single-store case but entirely reachable if an interactor is shared across features, which the DI
design actively encourages.

**Fix.** Build the stream eagerly in `init` and store it in a `let`, or place creation under the same
lock as S1-2.

---

### S1-4 · `strataCollect` tasks are never cancelled; every store instance leaks — Confirmed

`MESA/Sources/Strata/StrataConcurrency.swift:154-164` plus both sample stores.

`strataCollect` opens `Task.detached { for await value in stream { ... } }`. A detached task does not
inherit cancellation, and nothing in `TrapezioStore` cancels it. The task ends only when the stream
`finish()`es. None of the streams involved ever finish:

- `TrapezioMessageManager` has no `deinit` and never calls `continuation.finish()`
  (`TrapezioMessage.swift:50-67`)
- `StrataInteractor.inProgressStream` likewise (`StrataInteractor.swift:49-58`)
- `StrataSubjectInteractor.stream` likewise

So `SummaryStore.setupBindings()` (`SummaryStore.swift:43-54`) leaves two suspended detached tasks
alive for the process lifetime on every push to Summary. `CounterStore.setupBindings()` leaves one.
`[weak self]` prevents the *store* being retained but does nothing about the task, its closure
context, or the stream buffer it is parked on.

**Fix.** Two halves, both needed:

1. Give `TrapezioStore` a task bag and cancel it in `deinit`:

   ```swift
   private var tasks: [Task<Void, Never>] = []
   public func track(_ task: Task<Void, Never>) { tasks.append(task) }
   deinit { tasks.forEach { $0.cancel() } }
   ```

   with `collect(_:action:)` / `launch(work:reduce:)` instance methods that auto-track, so the free
   functions become the escape hatch rather than the default.

2. Give the stream owners a `deinit` that calls `finish()` on their continuations, so consumers
   terminate even when they weren't tracked.

Note that cancellation alone is not enough: `for await` on an `AsyncStream` does return `nil` on
cancellation, so (1) is sufficient for the task — but (2) is what makes an untracked consumer
survivable.

---

### S1-5 · `SummaryRepositoryImpl` accumulates observers forever — Confirmed

`Counter/Counter/Summary/Data/SummaryRepositoryImpl.swift:56-94`

`observeLastValue()` registers an entry in the actor's `observers` dictionary and removes it only
from `continuation.onTermination`. Per S1-4 the consuming stream never terminates, so `onTermination`
never fires and the entry is permanent.

The cost compounds: `notifyObservers()` (line 50) fans out to every registered continuation, and each
one triggers a `fetchCurrentValueSafe()` round-trip. After *N* visits to Summary, a single save does
*N* redundant SwiftData fetches. This is the sample app that adopters will copy.

**Fix.** Falls out of S1-4 once the collect tasks are cancelled — but the repository should also
bound its own exposure: key observers by a token the caller holds, and drop continuations whose
`yield` returns `.terminated`.

---

### S1-6 · A fresh `ModelContext` is allocated on every SwiftUI re-render — Confirmed

`Counter/Counter/Summary/SummaryFactory.swift:26-30`

```swift
static func make(screen: SummaryScreen, navigator: (any TrapezioNavigator)?) -> some View {
    let repo = SummaryRepositoryImpl(container: PersistenceService.shared.container)
    let saveUseCase = SaveLastValueUseCase(repository: repo)
    ...
    return TrapezioContainer(makeStore: SummaryStore(...), ui: SummaryUI())
}
```

`makeStore:` is `@autoclosure`, so store construction is correctly deferred to `@StateObject`. The
three lines above it are not — they execute on *every* evaluation of `make`, which SwiftUI calls on
every path change and every parent invalidation. `SummaryRepositoryImpl.init` builds a
`ModelContext` and a `DefaultSerialModelExecutor` each time, all of which are immediately discarded
because `@StateObject` keeps the first store.

`CounterFactory` has the same shape (`CounterFactory.swift:25`), though `DivideUsecase` is cheap
enough not to matter.

**Fix.** Move the whole graph inside the autoclosure:

```swift
TrapezioContainer(
    makeStore: {
        let repo = SummaryRepositoryImpl(container: PersistenceService.shared.container)
        return SummaryStore(screen: screen,
                            navigator: navigator,
                            saveUseCase: SaveLastValueUseCase(repository: repo),
                            observeUseCase: ObserveLastValueUseCase(repository: repo))
    }(),
    ui: SummaryUI()
)
```

The framework should also document this trap loudly — it is the single easiest way to misuse
`TrapezioContainer`, and the sample currently teaches the wrong version.

---

### S1-7 · `TrapezioMessageManager` never finishes its continuations — Confirmed

`MESA/Sources/Trapezio/TrapezioMessage.swift:50-67`

Each access to `messagesSequence` creates a new `AsyncStream` (default `.unbounded` buffering) and
registers a closure in `listeners`. There is no `deinit`. When the manager deallocates, `listeners`
goes with it and no continuation is ever finished, so every consumer stays parked forever.

Two secondary notes on the same type:

- `messagesSequence` being a **computed property** means `for await x in manager.messagesSequence`
  evaluated twice yields two independent registrations. Reading it inside a `body` would register a
  listener per render.
- `emit` drops the **oldest** message when at capacity (line 75), but `message` returns
  `messages.first` — also the oldest. Under a burst, the message currently on screen is the one
  chosen for eviction and disappears mid-display.

**Fix.** Add `deinit { listeners.values.forEach { ... }; continuations.forEach { $0.finish() } }`
(store continuations, not just the yield closures); make `messagesSequence` a stored `let` stream or
rename it `makeMessagesSequence()` so the allocation is visible at the call site; and either drop the
*newest* on overflow or expose the policy.

---

## S2 — Behavioural and design defects

### S2-1 · `StrataSubjectInteractor.stream` cannot support multiple accesses, but documents that it can — Confirmed

`MESA/Sources/Strata/StrataSubjectInteractor.swift:69-93`

```swift
/// - Important: Calling this property multiple times creates independent streams and tasks.
public var stream: AsyncStream<T> {
    AsyncStream { continuation in
        let task = Task { [weak self] in
            ...
            for await param in self.paramStream {   // <- shared, single-consumer
```

Each access does create a new outer `AsyncStream` and `Task` — but they all iterate the *same*
`paramStream`. `AsyncStream` supports one iterator; with two consumers each yielded parameter is
delivered to exactly one of them, arbitrarily. So two `.stream` accesses do not produce two
equivalent streams, they produce two streams that split the trigger sequence between them. The doc
comment says the opposite of what happens.

**Fix.** Either make `stream` a stored single instance and document it as single-consumer (matching
`inProgressStream`'s honest wording), or add real fan-out by keeping a set of downstream
continuations and broadcasting to all of them. Given `StrataSubjectInteractor` is the observation
primitive, broadcast is the more useful answer.

### S2-2 · The sample bypasses `StrataSubjectInteractor` entirely — Confirmed

`Counter/Counter/Summary/SummaryStore.swift:45`

```swift
let stream = observeUseCase.createObservable(params: ())
strataCollect(stream) { [weak self] val in ... }
```

`createObservable` is documented as the method you *override*, not the one you *call*
(`StrataSubjectInteractor.swift:95-101`); the public API is `callAsFunction(_:)` + `.stream`. Calling
it directly skips the re-trigger cancellation, the `value` cache, and the whole point of the type. As
written, `observeUseCase.value` would stay `nil` forever and `.stream` would never emit, because
`callAsFunction` is never invoked.

This is the reference implementation of the framework's own stream primitive, and it demonstrates not
using it.

### S2-3 · Nothing cancels in-flight work when a store dies — Confirmed

There is no `deinit`, no `cancel()`, no task bag, and no appear/disappear lifecycle on
`TrapezioStore`. Every `strataLaunch` in the samples captures `self` **strongly**
(`CounterStore.swift:66-67`, `SummaryStore.swift:62-70`), so a store survives past view teardown
until its work completes, then reduces into state nobody is observing.

For a framework whose pitch is "eliminate decision fatigue by enforcing clear separation of
concerns", leaving cancellation entirely to the adopter is the largest single gap. See S1-4 for the
proposed shape.

### S2-4 · The interactor timeout is soft, not a deadline — Confirmed

`MESA/Sources/Strata/StrataInteractor.swift:86-120`

`execute` races `doWork` against `Task.sleep` in a `withThrowingTaskGroup` and returns the first
result. But returning from the group body implicitly awaits the remaining child task. If `doWork`
does not honour cooperative cancellation — a synchronous CPU loop, a blocking C call, a
`URLSession` call without cancellation wiring — `execute` will not return until it finishes,
regardless of the configured timeout.

The tests only cover `Task.sleep`-based work (`StrataTimeoutTests.swift:122-125`), which cancels
promptly, so this never surfaces.

README line 321 states "the work task is cancelled", which is true, and implies the caller is
released, which is not.

**Fix.** Document it precisely, and add a test with a non-cancellable `doWork` asserting the actual
behaviour. If a hard deadline is wanted, `execute` must return on the timeout branch without awaiting
the work task — which means detaching it rather than using a child task.

### S2-5 · `inProgress` is not re-entrancy safe — Confirmed

`MESA/Sources/Strata/StrataInteractor.swift:90-91`

```swift
setInProgress(true)
defer { setInProgress(false) }
```

Two concurrent `execute` calls on one interactor: A sets `true`, B sets `true`, B finishes and sets
`false` while A is still running. Any bound spinner flickers off mid-flight. Interactors are
injected as shared singletons in the documented DI pattern, so concurrent execution is expected, not
exotic.

**Fix.** Refcount instead of flag: increment on entry, decrement on exit, publish `count > 0`.

### S2-6 · Double-tap pushes duplicate screens — Confirmed

`MESA/Sources/TrapezioNavigation/TrapezioNavigationHost.swift:70-86, 107-109`

`TrapezioAnyScreen` hashes and compares on a **fresh `UUID`**, so two pushes of an equal screen are
never equal and `goTo` appends unconditionally. Tapping "Go To Summary" twice quickly pushes Summary
twice — the classic iOS navigation bug, and one an opinionated framework is well placed to prevent.

**Fix.** Add a guard in `goTo` (skip if the top of the stack is an equal screen), or expose
`goTo(_:allowingDuplicates:)` defaulting to `false`. Note the UUID identity is doing useful work
elsewhere — deliberate duplicate pushes of the same route must stay possible — so a top-of-stack
check is the surgical version.

### S2-7 · `TrapezioScreen: Codable` funds a feature that does not exist — Confirmed

`TrapezioScreen.swift:31` sells `Codable` as enabling "serialization for deep links and state
restoration". Nothing in the library consumes it: `TrapezioAnyScreen` is not `Codable`, the path is
`[TrapezioAnyScreen]` rather than `NavigationPath`, and there is no restore or deep-link entry point.

Adopters pay the `Codable` conformance tax on every screen for a capability the framework does not
provide.

**Fix.** Either build it — a `Codable` type-erasure box with a screen-type registry, plus
`TrapezioNavigationHost(restoringFrom:)` — or drop the `Codable` requirement and the claim. Building
it is the higher-value option; deep-link support is table stakes for "out of the box".

### S2-8 · No lifecycle events, yet the docs' own example depends on one — Confirmed

README lines 385-393 show result consumption via `case .onAppear:`. `TrapezioUI.map` returns opaque
`Content` and `TrapezioRuntime` (`TrapezioRuntime.swift:33-37`) attaches nothing, so every adopter
must hand-wire `.onAppear { onEvent(.onAppear) }` in each UI and define the event themselves. There
is no `onFirstAppear` at all, which is what most "load on entry" code actually wants.

**Fix.** Add an optional lifecycle protocol the runtime can drive:

```swift
public protocol TrapezioLifecycle { 
    func onAppear()
    func onFirstAppear()
    func onDisappear()
}
```

with `TrapezioRuntime` applying `.onAppear`/`.onDisappear` when the store conforms. This also gives
`clearResults()` a natural home, which the navigator docs currently ask adopters to remember.

### S2-9 · `StrataException.localizedDescription` is shadowed when typed as `Error` — Confirmed

`MESA/Sources/Strata/StrataException.swift:27-31`

```swift
extension StrataException {
    public var localizedDescription: String { message }
}
```

Foundation already supplies `localizedDescription` via an extension on `Error`. Which one you get is
resolved **statically**. Through `any StrataException` you get `message`; through `any Error` you get
Foundation's bridged default — `"The operation couldn't be completed. (Module.MyError error 1.)"`.

So `TrapezioMessage(error)` (`TrapezioMessage.swift:30`), whose parameter is `Error`, will show the
useless string for a domain exception. The existing test
(`StrataTests.swift:181-186`) only checks the concrete-type path and passes.

The same trap bites `StrataExecutionException.init(error:)` (`StrataInteractor.swift:161-165`):
`error.localizedDescription` on a plain `struct PlainError: Error {}` produces the generic string, so
`message` is unhelpful for exactly the unexpected errors this type exists to describe.

**Fix.** Conform to `LocalizedError` and implement `errorDescription`, which *is* consulted through
the `Error` path:

```swift
public protocol StrataException: LocalizedError, Sendable {
    var message: String { get }
}
extension StrataException {
    public var errorDescription: String? { message }
}
```

Then delete the `localizedDescription` override.

### S2-10 · `TrapezioContainer`'s convenience init erases the concrete store type — Confirmed

`MESA/Sources/Trapezio/TrapezioContainer.swift:43-51`

The constraint is `Store == TrapezioStore<S, State, Event>`, so a concrete `CounterStore` is upcast
to the base class. Dynamic dispatch keeps `handle`/`update` working, but subclass API is unreachable
— you cannot get at `CounterStore.messageManager` (`CounterStore.swift:27`) from the container.

**Fix.** Add a generic parameter for the concrete store:

```swift
init<ConcreteStore: TrapezioStore<S, State, Event>, UI: TrapezioUI>(
    makeStore: @escaping @autoclosure () -> ConcreteStore,
    ui: UI
) where Store == ConcreteStore, ...
```

This also removes the `AnyView` wrapper in `content`.

### S2-11 · `TrapezioInterop` is unisolated while everything around it is `@MainActor` — Confirmed

`TrapezioInterop.swift:25-41` — the protocol has no isolation and no `Sendable` bound, while
`TrapezioNavigator` (`TrapezioNavigator.swift:21-22`) is `@MainActor`. `ClosureTrapezioInterop` is a
struct holding a non-`Sendable` closure, and stores hold `any TrapezioInterop` from `@MainActor`
context — so it works today by accident of where it's used, and invites a background-thread `send`
that the compiler won't catch.

**Fix.** Mark `TrapezioInterop` `@MainActor` to match the navigator, or make it explicitly `Sendable`
with a `@Sendable` handler if background sends are intended. Consistency matters more than which.

---

## S3 — Documentation contradicted by the code

### S3-1 · `strataRunCatching` cancellation is documented backwards — Confirmed

README line 315: *"`strataRunCatching` re-throws `CancellationError` rather than wrapping it in
`.failure`, allowing Swift's cooperative cancellation to propagate correctly."*

`CLAUDE.md` (and its three copies) says the same, and its table lists `strataRunCatching` as
`throws` / "Re-throws `CancellationError`".

The code (`StrataInteractor.swift:138-149`) does exactly the opposite — and is not even `throws`:

```swift
public func strataRunCatching<T>(_ block: () async throws -> T) async -> StrataResult<T> {
    ...
    } catch is CancellationError {
        return .failure(StrataCancellationException())
```

The test `cancellationErrorMapped` (`StrataTests.swift:131-140`) confirms the code's behaviour. So
all four instruction files are wrong. Same error propagates to `executeCatching`, documented at
`StrataInteractor.swift:124` as re-throwing.

Note also the README table (line 285) lists this function's cancellation behaviour as "—" while the
prose two paragraphs later describes re-throwing — the docs disagree with themselves as well as with
the code.

### S3-2 · `StrataExecutionException.underlyingError` does not exist — Confirmed

README line 312 and `CLAUDE.md` both say it "preserves `underlyingError`". The actual stored
properties are `underlyingErrorType: String` and `underlyingErrorDescription: String`
(`StrataInteractor.swift:156-165`). There is deliberately no `underlyingError` — the type stores a
`Sendable` snapshot instead, which is the right design but not what is documented.

### S3-3 · XCFrameworks are advertised but never built — Confirmed

README lines 87-97 promise `Trapezio.xcframework.zip`, `TrapezioNavigation.xcframework.zip`, and
`Strata.xcframework.zip` "attached to every GitHub Release", with install instructions.

`.github/workflows/publish-release.yml` runs `swift build` and `swift test` and uploads nothing.
`draft-release.yml` creates a notes-only draft. No workflow produces an `.xcframework`.

Anyone following the README's XCFramework path finds an empty release.

**Fix.** Either add an `xcodebuild -create-xcframework` job that attaches the archives on release, or
remove the section. The former is worth doing — it is the main reason a team would pick this over
vendoring the source.

### S3-4 · `StrataCancellationException` is undocumented — Confirmed

It exists (`StrataCancellationException.swift`), is returned by `strataRunCatching` and by `execute`
(`StrataInteractor.swift:116`), and is asserted in three tests. It appears in **neither** the README
error-type table (lines 309-313) nor `CLAUDE.md`'s. Adopters pattern-matching on failures will not
know to handle it.

### S3-5 · README install version lags `VERSION` — Confirmed

README line 68 shows `from: "0.1.0"`; `VERSION` is `0.2.0`.

### S3-6 · Four agent-instruction files, two of them already diverged — Confirmed

```
d65175d…  CLAUDE.md                        (226 lines)
e8370bd…  GEMINI.md                        (227 lines)
4d78e98…  .junie/guidelines.md             (227 lines)
4d78e98…  .github/copilot-instructions.md  (227 lines)
```

`CLAUDE.md` has already drifted from the other three. Maintaining four near-copies by hand
guarantees this widens, and all four currently carry the S3-1 and S3-2 errors.

**Fix.** Keep one canonical file and make the others symlinks, or generate them in CI from a shared
source with a check that fails when they differ.

### S3-7 · `TrapezioMessageManager` queue-overflow semantics are underspecified — Confirmed

Both README (line 257) and `CLAUDE.md` state the cap and FIFO drop correctly. Neither mentions that
the dropped message is the one `message` is currently returning (S1-7), which is the part that
actually affects UI behaviour.

### S3-8 · The iOS 16 minimum is never verified — Confirmed

`Package.swift:25` declares `.iOS(.v16)` and the README repeats it, but CI's only library job is
`swift test` on `macos-26` (`test.yml:21`), which compiles for macOS 13 exclusively. The
`Counter` app job builds for iOS but is pinned to `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. Nothing
anywhere compiles the libraries against the iOS 16 SDK.

**Fix.** Add `xcodebuild build -scheme Trapezio -destination 'generic/platform=iOS'` with
`IPHONEOS_DEPLOYMENT_TARGET=16.0` to CI.

---

## S4 — Hardening, hygiene, and gaps

### Security posture

The honest headline: this is a UI-architecture library with no networking, no crypto, no auth, and
zero third-party dependencies. There is no vulnerability here in the usual sense. What follows is
hardening.

**S4-1 · Workflow script injection surface — Confirmed.** `draft-release.yml:27, 36` interpolate
`${{ steps.version.outputs.version }}` directly into `run:` shell bodies. The value comes from the
`VERSION` file, so exploitation requires push access to `main` — low severity — but this is the
textbook GitHub Actions injection shape and the workflow holds `contents: write`. Pass the value
through `env:` and reference `"$VERSION"` instead.

**S4-2 · Default workflow permissions — Confirmed.** `test.yml` and `publish-release.yml` declare no
`permissions:` block and inherit the repository default, which on older repos is write-all. Add
`permissions: contents: read` to both.

**S4-3 · `persist-credentials` — Confirmed.** No `actions/checkout` step sets
`persist-credentials: false`, leaving the token in `.git/config` for subsequent steps. Cheap to fix.

**S4-4 · Logging is correctly private — Confirmed, no action needed.** `TrapezioNavigationHost.swift:135, 153`
interpolate screen descriptions and result keys into `os.Logger`. Dynamic strings default to
`.private` in the unified logging system, so screen parameters are redacted in persisted logs. This
is right. Worth a comment at the call site so nobody "fixes" it to `.public` or swaps in `print`,
which would put route parameters in plaintext.

**S4-5 · SwiftData store has no file protection — Confirmed.**
`PersistenceService.swift:30` uses `ModelConfiguration(schema:isStoredInMemoryOnly: false)` with no
file-protection class. For a template that adopters copy, demonstrating
`FileProtectionType.complete` would set the right default.

**S4-6 · `fatalError` on container failure — Confirmed.** `PersistenceService.swift:35` crashes the
app if the store can't open — disk full, failed migration, corrupt file. A reference app should model
graceful degradation instead.

**S4-7 · No `SECURITY.md`.** No disclosure path for a library published to GitHub Releases.

### Framework completeness gaps

For "out of the box", these are the missing pieces adopters will hit in week one:

**S4-8 · No DI story.** `CLAUDE.md` says "Use **Factories** to assemble generic graphs" and the
samples build graphs by hand inside a `static func make`. That is fine at two features and painful at
twenty. A `TrapezioFactory` protocol plus a screen→factory registry (which also feeds the deep-link
work in S2-7) would close it.

**S4-9 · No `TrapezioContainer` / `TrapezioRuntime` / `TrapezioNavigationHost` tests.** Test coverage
of the pure logic is good; the SwiftUI integration layer — where store identity and lifecycle live,
and where S1-6 and S2-6 hide — has none.

**S4-10 · `updateSkipsWhenEqual` does not test what it claims.** `TrapezioTests.swift:44-52` asserts
only the final value; the `objectWillChange` suppression that is the whole point of the `Equatable`
check goes unverified. Subscribe to `objectWillChange` and count emissions.

**S4-11 · `awaitState` fails silently on timeout.** `TrapezioStoreTestExtension.swift:46-56` validates
the current state after the deadline whether or not the predicate ever held, turning a hang into a
confusing assertion failure elsewhere. Add an `Issue.record` on timeout, or return a `Bool`.

**S4-12 · Missing repo furniture.** No `CONTRIBUTING.md`, no `CHANGELOG.md`, no DocC catalog, no
SwiftLint/swift-format config. `Package.swift` does not declare `swiftLanguageMode` explicitly (it
inherits `.v6` from tools-version 6.2 — worth pinning so an adopter's toolchain change can't silently
relax it), and omits watchOS/tvOS/visionOS.

### Sample-app polish — all Confirmed

| Location | Issue |
|:---|:---|
| `CounterStore.swift:31-33` | `MockError` declared, never used |
| `CounterStore.swift:54-55` | `// Bind UseCase stream` — empty comment, no code |
| `CounterStore.swift:73` | `case .throwError: // Needs to be added to Event enum first, usually` — stale note; it *is* in the enum |
| `CounterUi.swift:75` | `.background(Color.white)` hardcoded — breaks dark mode; use `Color(.systemBackground)` |
| `SummaryUi.swift:30-31` | Empty `HStack(spacing: 16) { }` |
| `SummaryRepositoryImpl.swift:35` | `saveValue` fetches unsorted and takes `.first`; `fetchCurrentValueSafe` (line 98) sorts by `timestamp` descending. Different rows on a multi-row store |
| `CounterUITests.swift:146-152` | `testExample` is the Xcode stub — asserts nothing |
| `.gitignore` | `*.lock` is broad enough to swallow lockfiles a consumer may want tracked |

---

## Proposed stacked PRs

Ordered so each rests on the one before. Stack 1 and 2 are the ones that matter.

**PR 1 — Store lifecycle and cancellation** *(fixes S1-4, S2-3; unblocks the rest)*
Task bag on `TrapezioStore` with `deinit` cancellation; `collect`/`launch` instance methods that
auto-track; `deinit`-based `finish()` on `TrapezioMessageManager`, `StrataInteractor.inProgressStream`,
and `StrataSubjectInteractor`. Tests asserting tasks terminate on store deallocation.

**PR 2 — Concurrency safety** *(S1-1, S1-2, S1-3, S2-5)*
Remove `nonisolated(unsafe)` from `state` and add the snapshot-based `launch` overload; move
`inProgressContinuation` under the existing lock; eager-init `inProgressStream`; refcount
`inProgress`. Depends on PR 1 for the instance-method surface.

**PR 3 — Strata correctness** *(S2-1, S2-4, S2-9, S3-1, S3-2, S3-4)*
Broadcast `StrataSubjectInteractor.stream` or document single-consumer honestly; `LocalizedError`
conformance for `StrataException`; correct the cancellation and `underlyingError` documentation
across all four instruction files; document the soft-timeout semantics with a non-cancellable test.

**PR 4 — Navigation completeness** *(S2-6, S2-7, S2-8)*
Top-of-stack duplicate guard; lifecycle protocol driven by `TrapezioRuntime`; `Codable` path
serialisation with a screen registry, or removal of the `Codable` requirement. Largest design surface
— worth its own discussion before coding.

**PR 5 — Sample app rewrite** *(S1-5, S1-6, S2-2, S2-10, sample polish)*
Move graph construction inside the autoclosure; use `callAsFunction`/`.stream` properly; bound the
repository's observers; generic `TrapezioContainer` init; clear the dead code and dark-mode bug.
Lands after 1-4 so it demonstrates the fixed APIs.

**PR 6 — CI, release, and docs** *(S3-3, S3-5, S3-6, S3-8, S4-1, S4-2, S4-3, S4-9, S4-12)*
XCFramework build-and-attach; iOS 16 compile job; workflow permissions and injection hardening;
single-source the agent instruction files; SwiftUI-layer tests; repo furniture.

---

*Review performed by static reading only — no build or test run was possible in the review
environment. Recommend re-confirming S2-4 and S1-3 against a real toolchain before acting on them.*
