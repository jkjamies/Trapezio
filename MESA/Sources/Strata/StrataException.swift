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

import Foundation

// MARK: - StrataException

/// Base error type for all Strata business logic failures.
///
/// Refines `LocalizedError` rather than plain `Error` on purpose. Foundation supplies a
/// `localizedDescription` on every `Error`, and which implementation you get is resolved
/// *statically* — so a protocol extension defining `localizedDescription` here would be
/// silently bypassed the moment a value is typed as `any Error` (for example when passed to
/// `TrapezioMessage(_:)`), yielding "The operation couldn't be completed…" instead of
/// ``message``. `LocalizedError.errorDescription` is consulted through the `Error` path, so
/// conforming here makes ``message`` authoritative everywhere.
public protocol StrataException: LocalizedError, Sendable {
    var message: String { get }
}

extension StrataException {
    /// Bridges ``message`` into Foundation's error-description machinery.
    public var errorDescription: String? { message }
}
