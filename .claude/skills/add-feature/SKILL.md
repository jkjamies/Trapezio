---
name: add-feature
description: Scaffold a new feature module with the appropriate layers and MESA conventions
disable-model-invocation: true
argument-hint: "<feature-name> [--headless]"
---

# Add Feature

Scaffold a new feature module with the correct directory structure and DI wiring following MESA conventions.

**Input:** $ARGUMENTS

---

## Step 1: Determine Feature Name and App Target

Identify the **app target** (`<AppTarget>`) by looking at the Xcode project's main application target (e.g., `Counter` for the sample app). This is the folder that contains the app's feature modules — not the Swift package (`MESA`).

Extract the feature name from the input (e.g., `Profile`). This becomes:
- Directory: `<AppTarget>/<FeatureName>/`
- Naming prefix: PascalCase feature name (e.g., `Profile` → `ProfileScreen`, `ProfileStore`, etc.)

---

## Step 2: Determine Layers

**If `--headless` is provided:** Default to `Domain` + `Data` (no presentation). Ask the user to confirm, or if any of these should also be excluded.

**If no flags are provided:** Ask the user which layers this feature needs:

> Which layers does this feature need?
> 1. **Full feature** — `Domain` + `Data` + `Presentation` (UI with Store, Screen, Events)
> 2. **Headless library** — `Domain` + `Data` (no UI)
> 3. **Custom** — Let me pick individual layers
>
> For custom, which layers? (e.g., "Domain, Presentation")

If the user selects custom, also ask follow-up questions based on the selected layers:
- If `Domain` is included: "Does this feature need Strata interactors?"
- If `Data` is included: "Does this feature need a repository?"
- If `Data` is included: "Does this feature need SwiftData persistence?"

---

## Step 3: Scaffold Directory Structure

Create the module directories and files based on the selected layers. **Do not scaffold presentation layer files directly** — that is handled by the `/add-screen` skill in Step 5.

### `Domain/` layer

```
<AppTarget>/<FeatureName>/Domain/
```

The `Domain` module contains pure Swift business logic. No UI framework imports (no SwiftUI, SwiftData, UIKit). Foundation is allowed. Repository protocols and use cases live here.

### `Data/` layer

```
<AppTarget>/<FeatureName>/Data/
```

The `Data` module contains repository implementations using `actor` isolation. Depends only on `Domain`.

### `Presentation/` layer (directory only)

If presentation is included, create only the directory shell:

```
<AppTarget>/<FeatureName>/
```

The actual Screen, State, Event, Store, UI, and Factory files are created by the `/add-screen` skill in Step 5.

---

## Step 4: Create Domain & Data Files (if applicable)

### Repository Protocol (if data layer included)

Place at: `<AppTarget>/<FeatureName>/Domain/<FeatureName>Repository.swift`

```swift
import Foundation

public protocol <FeatureName>Repository: Sendable {
    // Define data operations
}
```

### Repository Implementation (if data layer included)

Place at: `<AppTarget>/<FeatureName>/Data/<FeatureName>RepositoryImpl.swift`

**Without persistence:**
```swift
import Foundation

public actor <FeatureName>RepositoryImpl: <FeatureName>Repository {
    public init() {}

    // Implement protocol methods
}
```

**With SwiftData persistence:**
```swift
import Foundation
import SwiftData

public actor <FeatureName>RepositoryImpl: <FeatureName>Repository, ModelActor {
    public let modelContainer: ModelContainer
    public let modelExecutor: any ModelExecutor

    public init(container: ModelContainer) {
        self.modelContainer = container
        let context = ModelContext(container)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    // Implement protocol methods
}
```

---

## Step 5: Delegate to Other Skills

After scaffolding the module structure (delegated skills handle their own license headers):

1. **If presentation is included:** Automatically run the `/add-screen` skill to scaffold the first screen. Offer the user two options for the screen name:
   - **Default:** `<FeatureName>Screen` (e.g., feature `Settings` → `SettingsScreen`)
   - **Custom:** Let the user type their own name

2. **If domain is included and interactors are needed:** Repeat the following loop:
   - Ask: "Would you like to add an interactor? (yes/no)"
   - If yes:
     1. Offer two options for the name:
        - **Default:** `<FeatureName><Action>UseCase` based on common patterns (e.g., `FetchSettingsUseCase`)
        - **Custom:** Let the user type their own name
     2. Ask: "Is this a one-shot operation or an observable stream?"
        - **One-shot** → `StrataInteractor` (no flag)
        - **Observable** → `StrataSubjectInteractor` (`--observe`)
     3. Run `/add-interactor <feature-name> <InteractorName> [--observe]`
     4. Loop back and ask if they want to add another interactor
   - If no, proceed to the next step

---

## Step 6: License Headers

All source files generated directly by this skill MUST include the Apache 2.0 license header. Files generated by delegated skills (`/add-screen`, `/add-interactor`) handle their own headers.

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

Run `cd MESA && swift build` to verify the package compiles. If app target files were changed, also run `xcodebuild build -scheme <AppTarget> -destination 'platform=iOS Simulator,name=<SimulatorDevice>'` (e.g., `-scheme Counter -destination 'platform=iOS Simulator,name=iPhone 17'`).

Report:
- Which directories and files were created
- Which files were generated by delegated skills
