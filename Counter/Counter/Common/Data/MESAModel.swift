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

@Model
public final class MESAModel {
    public var lastSavedValue: Int
    public var timestamp: Date
    
    public init(lastSavedValue: Int, timestamp: Date = Date()) {
        self.lastSavedValue = lastSavedValue
        self.timestamp = timestamp
    }
}
