---
name: add-screen
description: Add a new screen to an existing feature module with Store, UI, factories, and tests
disable-model-invocation: true
argument-hint: "<feature-name> <ScreenName>"
---

# Add Screen

Add a new screen to an existing feature module. This scaffolds the Screen, State, Event, Store, UI, and Factory within the feature's directory.

**Input:** $ARGUMENTS

---

## Step 1: Validate the Feature

Extract the feature name and screen name from the input.

Verify the feature directory exists at `<AppTarget>/<FeatureName>/`. If the feature doesn't exist, suggest running `/add-feature` first.

---

## Step 2: Read Existing Patterns

Read the existing screen files in the feature module to match:
- Import patterns
- Store constructor patterns (what dependencies are injected)
- Factory registration patterns

Also read existing screens from other features if the current feature has no prior screens.

---

## Step 3: Determine Screen Details

Ask the user:
1. Does this screen receive navigation arguments? If so, what are they? (These become properties on the `TrapezioScreen` struct)
2. Does this screen need `TrapezioNavigator` injection?
3. Does this screen need `TrapezioInterop` injection?

---

## Step 4: Create Files

### Screen + State + Event

Place at: `<AppTarget>/<FeatureName>/<ScreenName>Screen.swift`

```swift
import Trapezio

struct <ScreenName>Screen: TrapezioScreen {
    // navigation arguments as properties (must be Hashable & Codable)
}

struct <ScreenName>State: TrapezioState {
    // display properties — value types only, must be Equatable
}

enum <ScreenName>Event: TrapezioEvent {
    // user intents
}
```

### Store

Place at: `<AppTarget>/<FeatureName>/<ScreenName>Store.swift`

```swift
import Foundation
import Trapezio
import TrapezioNavigation
import Strata

@MainActor
final class <ScreenName>Store: TrapezioStore<<ScreenName>Screen, <ScreenName>State, <ScreenName>Event>, TrapezioLifecycle {
    private let navigator: (any TrapezioNavigator)?
    // injected dependencies

    init(
        screen: <ScreenName>Screen,
        navigator: (any TrapezioNavigator)?
        // additional dependencies
    ) {
        self.navigator = navigator
        super.init(screen: screen, initialState: <ScreenName>State(/* initial values */))
    }

    // Observation starts on first appearance, not in `init`. `collect` tracks the task in the
    // store's TrapezioTaskBag, so it is cancelled when the store deallocates.
    func onFirstAppear() {
        // collect(useCase.stream) { [weak self] value in self?.update { $0.field = value } }
        // Subscribe before triggering — `stream` broadcasts live emissions and does not replay.
    }

    // Consume navigation results here: onAppear also fires when this screen is revealed by a pop.
    func onAppear() {
        // if let result = navigator?.consumeResult(forKey: "key", as: SomeResult.self) { ... }
    }

    override func handle(event: <ScreenName>Event) {
        switch event {
        // handle events
        //
        // Detached work cannot read `state`. Snapshot it on the main actor first:
        // launch(
        //     snapshot: { $0.field },
        //     work: { value in await useCase.execute(params: value) },
        //     reduce: { [weak self] result in self?.update { $0.other = result.getOrNull() } }
        // )
        }
    }
}
```

### UI

Place at: `<AppTarget>/<FeatureName>/<ScreenName>Ui.swift`

```swift
import SwiftUI
import Trapezio

struct <ScreenName>UI: TrapezioUI {
    func map(state: <ScreenName>State, onEvent: @escaping @MainActor (<ScreenName>Event) -> Void) -> some View {
        // stateless composable — no @State, no side effects, no business logic
    }
}
```

### Factory

Place at: `<AppTarget>/<FeatureName>/<ScreenName>Factory.swift`

```swift
import SwiftUI
import Trapezio
import TrapezioNavigation

struct <ScreenName>Factory {
    @MainActor
    static func make(screen: <ScreenName>Screen, navigator: (any TrapezioNavigator)?, interop: (any TrapezioInterop)?) -> some View {
        TrapezioContainer(
            makeStore: {
                // Assemble the ENTIRE graph inside the autoclosure. Anything built in the
                // surrounding body runs on every view evaluation and is then discarded —
                // expensive for repositories, ModelContexts, and network clients.
                let repository = <FeatureName>RepositoryImpl(/* ... */)
                return <ScreenName>Store(
                    screen: screen,
                    navigator: navigator,
                    useCase: <Something>UseCase(repository: repository)
                )
            }(),
            ui: <ScreenName>UI()
        )
    }
}
```

If the store has no dependencies to assemble, the shorter form is fine — the autoclosure still
defers construction:

```swift
TrapezioContainer(
    makeStore: <ScreenName>Store(screen: screen, navigator: navigator),
    ui: <ScreenName>UI()
)
```

---

## Step 5: Register in Navigation

Add the screen to the `ContentView` builder closure:

```swift
case let <name> as <ScreenName>Screen:
    <ScreenName>Factory.make(screen: <name>, navigator: navigator, interop: interop)
```

---

## Step 6: Generate Tests

Automatically generate test files following the conventions from the `/add-tests` skill:

### Store Unit Test

For Counter app (XCTest):

```swift
import XCTest
import Trapezio
import TrapezioNavigation
@testable import <AppTarget>

@MainActor
final class <ScreenName>StoreTests: XCTestCase {

    var store: <ScreenName>Store!

    override func setUp() {
        super.setUp()
        let screen = <ScreenName>Screen(/* params */)
        store = <ScreenName>Store(
            screen: screen,
            /* inject fakes */
            navigator: nil
        )
    }

    func test_initialState_isCorrect() {
        // assert initial state
    }
}
```

For MESA library (Swift Testing) — use `TrapezioTest` utilities when testing navigation:

```swift
import Foundation
import Testing
import TrapezioTest
@testable import <Target>

@Suite("<ScreenName>Store")
struct <ScreenName>StoreTests {

    @Test("initial state is correct")
    @MainActor func initialState() {
        let store = <ScreenName>Store(
            screen: <ScreenName>Screen(/* params */),
            navigator: nil
        )
        #expect(store.state == <ScreenName>State(/* expected */))
    }

    // Use FakeTrapezioNavigator to assert navigation:
    // let nav = FakeTrapezioNavigator()
    // store.handle(event: .someNavEvent)
    // #expect(nav.navigatedScreens.count == 1)
}
```

---

## Step 7: License Headers

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

## Step 8: Verify

Run `cd MESA && swift build` to verify compilation.

Report:
- Which files were created
- Screen navigation arguments (if any)

Then ask:
- "Would you like to add interactors for this screen?" → suggest running `/add-interactor <feature-name> <InteractorName>`
