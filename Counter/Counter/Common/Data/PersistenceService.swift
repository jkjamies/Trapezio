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

import SwiftData
import Foundation
import os

private let logger = Logger(subsystem: "Counter", category: "Persistence")

public final class PersistenceService {
    public static let shared = PersistenceService()

    public let container: ModelContainer

    /// `true` when the on-disk store could not be opened and an in-memory fallback is in use.
    /// Surface this in the UI if losing data between launches would matter to the user.
    public let isEphemeral: Bool

    private init() {
        let schema = Schema([
            MESAModel.self,
        ])
        // Application Support is not guaranteed to exist on iOS, and SwiftData will not create
        // intermediate directories for an explicit store URL — without this the container fails
        // to open and we silently fall back to in-memory.
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "MESA.store")

        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            isEphemeral = false
            Self.applyFileProtection(to: storeURL)
        } catch {
            // A failed migration, a corrupt store, or a full disk should not take the app down
            // with it. Degrade to in-memory so the user can keep working, and record that we did.
            logger.error("Falling back to an in-memory store: \(error.localizedDescription)")
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            isEphemeral = true
        }
    }

    /// Restricts the store to times the device is unlocked, or was unlocked when the file was
    /// opened. SwiftData applies no protection class of its own.
    private static func applyFileProtection(to url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: url.path
            )
        } catch {
            logger.warning("Could not set file protection on the store: \(error.localizedDescription)")
        }
    }
}
