---
name: add-interactor
description: Scaffold a new Strata interactor with interface, implementation, fake, and test
disable-model-invocation: true
argument-hint: "<feature-name> <InteractorName> [--observe]"
---

# Add Interactor

Scaffold a new Strata interactor for an existing feature module, including the implementation, fake, and test.

**Input:** $ARGUMENTS

---

## Step 1: Parse Input

Extract:
- **Feature name:** The feature module to add the interactor to (e.g., `Summary`)
- **Interactor name:** The name of the interactor (e.g., `FetchUser`, `ObserveLastSavedValue`)
- **Type:**
  - No flag → `StrataInteractor` (one-shot async, returns `StrataResult<R>`)
  - `--observe` → `StrataSubjectInteractor` (stream, exposes `AsyncStream<T>` via `.stream`)

`createObservable(params:)` is the method you **override**, never the one you call. Consumers
trigger with `callAsFunction(_:)` and read `.stream`; calling `createObservable` directly bypasses
re-trigger cancellation and the `value` cache. `.stream` broadcasts to every subscriber and does
not replay, so subscribe before triggering.

Verify the feature module exists at `<AppTarget>/<FeatureName>/`. If it doesn't exist, **stop and ask the user** whether they intended a different feature name or whether they need to create the feature first with `/add-feature`. Do not proceed until the feature exists.

---

## Step 2: Determine Parameters and Return Types

Ask the user:
1. What is the input parameter type? (e.g., `Int`, `String`, `Void`)
2. What is the return/output type? (e.g., `User`, `[Item]`, `Int?`)

---

## Step 3: Read Existing Module Structure

Read the feature module's existing files to understand:
- Import patterns
- Any existing interactors to match style
- Repository dependencies

---

## Step 4: Create Files

### Implementation in `Domain/`

Place at: `<AppTarget>/<FeatureName>/Domain/<InteractorName>UseCase.swift`

**StrataInteractor (one-shot):**
```swift
import Foundation
import Strata

public final class <InteractorName>UseCase: StrataInteractor<P, R> {

    private let repository: <FeatureName>Repository

    public init(repository: <FeatureName>Repository) {
        self.repository = repository
        super.init()
    }

    public override func doWork(params: P) async -> StrataResult<R> {
        return await executeCatching(params: params) { p in
            try await repository.someMethod(p)
        }
    }
}
```

**StrataSubjectInteractor (observe):**
```swift
import Foundation
import Strata

public class <InteractorName>UseCase: StrataSubjectInteractor<P, T> {

    private let repository: <FeatureName>Repository

    public init(repository: <FeatureName>Repository) {
        self.repository = repository
        super.init()
    }

    public override func createObservable(params: P) -> AsyncStream<T> {
        return repository.observe()
    }
}
```

### Fake in test directories

Place in the consuming module's test directory under a `Fakes/` subdirectory (e.g., `<AppTarget>Tests/Fakes/Fake<InteractorName>UseCase.swift`). Typically this is the app's test target.

**StrataInteractor Fake:**
```swift
import Foundation
import Strata
@testable import <AppTarget>

final class Fake<InteractorName>UseCase: StrataInteractor<P, R>, @unchecked Sendable {
    var stubResult: StrataResult<R> = .success(/* default value */)

    override func doWork(params: P) async -> StrataResult<R> {
        return stubResult
    }
}
```

**StrataSubjectInteractor Fake:**
```swift
import Foundation
import Strata
@testable import <AppTarget>

final class Fake<InteractorName>UseCase: StrataSubjectInteractor<P, T>, @unchecked Sendable {
    var values: [T] = []

    override func createObservable(params: P) -> AsyncStream<T> {
        AsyncStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}
```

### Unit Test in test target

Place at: `<AppTarget>Tests/<InteractorName>UseCaseTests.swift`

**For MESA library tests (Swift Testing):**
```swift
import Foundation
import Testing
@testable import <AppTarget>

@Suite("<InteractorName>UseCase")
struct <InteractorName>UseCaseTests {

    @Test("executes successfully with valid params")
    func executeSuccess() async {
        // Given
        let useCase = <InteractorName>UseCase(repository: FakeRepository())

        // When
        let result = await useCase.execute(params: /* test params */)

        // Then
        #expect(result.getOrNull() == /* expected value */)
    }

    @Test("returns failure on repository error")
    func executeFailure() async {
        // Given
        let useCase = <InteractorName>UseCase(repository: FailingFakeRepository())

        // When
        let result = await useCase.execute(params: /* test params */)

        // Then
        #expect(result.getOrNull() == nil)
    }
}
```

**For Counter app tests (XCTest):**
```swift
import XCTest
@testable import Counter

final class <InteractorName>UseCaseTests: XCTestCase {

    func test_execute_succeeds() async {
        // Given
        let useCase = <InteractorName>UseCase(repository: FakeRepository())

        // When
        let result = await useCase.execute(params: /* test params */)

        // Then
        XCTAssertEqual(result.getOrNull(), /* expected value */)
    }
}
```

For `StrataSubjectInteractor`, test the stream output:
```swift
@Test("emits values from createObservable")
func basicEmission() async {
    let useCase = <InteractorName>UseCase(repository: FakeRepository())

    let task = Task { () -> [T] in
        var collected: [T] = []
        for await value in useCase.stream {
            collected.append(value)
            if collected.count >= 1 { break }
        }
        return collected
    }

    try? await Task.sleep(nanoseconds: 10_000_000)
    useCase(/* params */)

    let collected = await task.value
    #expect(collected == [/* expected */])
}
```

---

## Step 5: License Headers

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

## Step 6: Verify

Run `cd MESA && swift test --parallel` for the affected modules to verify compilation.

Report:
- Which files were created
- The interactor type (one-shot or observe)
- Parameter and return types
- Where the fake was placed
