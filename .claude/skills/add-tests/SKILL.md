---
name: add-tests
description: Add missing test cases, targeting a specific file or all changed files on the branch
disable-model-invocation: true
argument-hint: "[@<filepath>] [--unit] [--ui]"
---

# Add Tests

Add test coverage for a specific file or for all testable files changed on the branch. If test files already exist, analyze them for missing test cases and add them. If no test files exist, create them from scratch.

**Input:** $ARGUMENTS

---

## Step 1: Determine Targets

**If a file path is provided:** Use that file as the single target.

**If no file path is provided:** Run `git diff main --name-only` to get all changed files on the branch. Filter to testable source files (Stores, Interactors, UseCases, Repositories). Exclude test files, build files, and configuration. Process each testable file.

---

## Step 2: Analyze Each Target

For each target file, read it and understand:
- The component type (Store, Interactor, UseCase, Repository, etc.)
- The State, Event, and Screen types involved
- Dependencies that need faking
- The module path (MESA library vs Counter app)
- Every public method, event, state property, and code path

Determine which test types apply:
- `--unit` → Unit tests only
- `--ui` → UI tests only (XCTest UI)
- No flag → Auto-detect based on component type:

| Component | Test Type | Location |
|-----------|-----------|----------|
| **Store** | Unit | `<AppTarget>Tests/` |
| **StrataInteractor** | Unit | `<AppTarget>Tests/` or `MESA/Tests/` |
| **StrataSubjectInteractor** | Unit | `<AppTarget>Tests/` or `MESA/Tests/` |
| **Protocol UseCase** | Unit | `<AppTarget>Tests/` |
| **Repository Impl** | Unit | `<AppTarget>Tests/` |
| **UI Composable** | UI | `<AppTarget>UITests/` |

---

## Step 3: Check for Existing Tests

Search for existing test files:
- For `{Name}Store.swift` → look for `{Name}StoreTests.swift`
- For `{Name}UseCase.swift` → look for `{Name}UseCaseTests.swift`
- For `{Name}Ui.swift` → look for corresponding UI tests

Also check for existing Fake files in `Fakes/` subdirectories.

**If test files exist:** Read them and compare against the implementation to identify:
- Events or state transitions not covered
- Code branches or error paths not tested
- New methods or behaviors added but missing from tests
- Missing Fake files for new dependencies

**If test files do not exist:** Create them from scratch following the patterns below.

---

## Step 4: Determine Test Framework

- **MESA library** (`MESA/Sources/`): Swift Testing (`@Suite`, `@Test`, `#expect`)
- **Counter app** (`Counter/`): XCTest (`XCTestCase`, `XCTAssertEqual`)

---

## Step 5: Generate / Update Unit Tests

### Store Test Pattern (XCTest — Counter app)

```swift
import XCTest
import Trapezio
import TrapezioNavigation
@testable import <AppTarget>

@MainActor
final class <Name>StoreTests: XCTestCase {

    var store: <Name>Store!

    override func setUp() {
        super.setUp()
        let screen = <Name>Screen(/* params */)
        store = <Name>Store(
            screen: screen,
            /* inject fakes */
            navigator: nil
        )
    }

    func test_<eventName>_<expectedBehavior>() {
        store.handle(event: .<eventCase>)
        XCTAssertEqual(store.state.<field>, <expectedValue>)
    }

    func test_<asyncEvent>_updatesState() async throws {
        store.handle(event: .<asyncEvent>)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms for the store's detached launch
        XCTAssertEqual(store.state.<field>, <expectedValue>)
    }
}
```

### Store Test Pattern (Swift Testing — MESA library)

```swift
import Foundation
import Testing
@testable import <Target>

@Suite("<Name>Store")
struct <Name>StoreTests {

    @Test("initial state is correct")
    @MainActor func initialState() {
        let store = <Name>Store(screen: <Name>Screen(), navigator: nil)
        #expect(store.state == <Name>State(/* expected */))
    }

    @Test("<eventName> mutates state correctly")
    @MainActor func <eventName>() {
        let store = <Name>Store(screen: <Name>Screen(), navigator: nil)
        store.handle(event: .<eventCase>)
        #expect(store.state.<field> == <expectedValue>)
    }
}
```

### Interactor Test Pattern (Swift Testing)

```swift
import Foundation
import Testing
@testable import <AppTarget>

@Suite("<Name>UseCase")
struct <Name>UseCaseTests {

    @Test("executes successfully")
    func executeSuccess() async {
        let useCase = <Name>UseCase(/* faked dependencies */)
        let result = await useCase.execute(params: /* params */)
        #expect(result.getOrNull() == /* expected */)
    }

    @Test("returns failure on error")
    func executeFailure() async {
        let useCase = <Name>UseCase(/* failing fakes */)
        let result = await useCase.execute(params: /* params */)
        #expect(result.getOrNull() == nil)
    }
}
```

### Interactor Test Pattern (XCTest)

```swift
import XCTest
@testable import Counter

final class <Name>UseCaseTests: XCTestCase {

    func test_execute_succeeds() async {
        // Given
        let useCase = <Name>UseCase(/* dependencies */)
        // When
        let result = await useCase.execute(params: /* params */)
        // Then
        XCTAssertEqual(result.getOrNull(), /* expected */)
    }
}
```

### StrataSubjectInteractor Test Pattern

```swift
@Test("emits values for each trigger")
func basicEmission() async {
    let interactor = <Name>UseCase(/* dependencies */)

    let task = Task { () -> [T] in
        var collected: [T] = []
        for await value in interactor.stream {
            collected.append(value)
            if collected.count >= 1 { break }
        }
        return collected
    }

    try? await Task.sleep(nanoseconds: 10_000_000)
    interactor(/* params */)

    let collected = await task.value
    #expect(collected == [/* expected */])
}
```

### Fake Creation

When dependencies need faking, create Fake classes in a `Fakes/` subdirectory:

- Implement the protocol directly or subclass the interactor
- Remove delays for deterministic testing
- Provide controllable state (e.g., `stubResult` property, `sentEvents` capture array)
- Mark `@unchecked Sendable` where needed for concurrency tests
- **Prefer `TrapezioTest` library utilities** when available:
  - `FakeTrapezioNavigator` — records all navigation events (`goTo`, `dismiss`, `popWithResult`, etc.) for assertion
  - `TestEventSink<E>` — records events via `callAsFunction`, provides `.events`, `.last`, `.count`
  - `TrapezioStore.test { state in }` — headless state assertion without UI
  - `TrapezioStore.awaitState(until:validate:)` — waits for async state changes before asserting. It returns `Bool`; assert on it so a timeout reads as a timeout rather than a confusing assertion failure

Stores that conform to `TrapezioLifecycle` start observation in `onFirstAppear()`, which the
runtime calls from the view. A headless test has no view, so call it explicitly:

```swift
let store = <Name>Store(screen: <Name>Screen(), navigator: nil)
store.onFirstAppear()   // start observation the way the runtime would
```

```swift
import Foundation
@testable import <AppTarget>

struct Fake<Dependency>: <DependencyProtocol> {
    func execute(<params>) async -> <ReturnType> {
        return <stubValue> // No Task.sleep — instant for testing
    }
}
```

```swift
import Foundation
import Trapezio
import TrapezioNavigation
@testable import <AppTarget>

// TrapezioInterop is @MainActor, so conformers must match its isolation.
@MainActor
final class FakeInterop: TrapezioInterop {
    var sentEvents: [any TrapezioInteropEvent] = []
    func send(_ event: any TrapezioInteropEvent) {
        sentEvents.append(event)
    }
}
```

---

## Step 6: License Header

All generated files MUST include the Apache 2.0 license header:

```swift
/*
 * Copyright 2026 Jason Jamieson
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
```

---

## Step 7: Verify

After generating or updating tests, attempt to compile:
- MESA library: `cd MESA && swift test --parallel`
- Counter app: Report the run command to the user: `xcodebuild test -scheme Counter -destination 'platform=iOS Simulator,name=iPhone 17'`

Fix any compilation issues before finishing.
