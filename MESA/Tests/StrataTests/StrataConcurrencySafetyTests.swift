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
import Testing
@testable import Strata

/// Interactor whose work duration is supplied per call.
private final class FakeDurationInteractor: StrataInteractor<TimeInterval, String>, @unchecked Sendable {
    override func doWork(params: TimeInterval) async -> StrataResult<String> {
        try? await Task.sleep(for: .seconds(params))
        return .success("done")
    }
}

// MARK: - inProgress refcounting

@Suite("StrataInteractor concurrent execution")
struct StrataInteractorConcurrencyTests {

    @Test("a finished execution does not clear inProgress while another is running")
    func inProgressIsRefcounted() async {
        let interactor = FakeDurationInteractor()

        let long = Task { await interactor.execute(params: 0.4) }
        try? await Task.sleep(for: .milliseconds(50))

        let short = Task { await interactor.execute(params: 0.01) }
        _ = await short.value

        // The short call has completed, but the long one has not — a plain boolean flag would
        // have been cleared here.
        #expect(interactor.inProgress == true)

        _ = await long.value
        #expect(interactor.inProgress == false)
    }

    @Test("inProgressStream finishes when the interactor deallocates")
    func progressStreamFinishesOnDeinit() async {
        var interactor: FakeDurationInteractor? = FakeDurationInteractor()
        let stream = interactor!.inProgressStream

        let collector = Task { () -> Int in
            var count = 0
            // Only returns once the stream finishes, which is the behaviour under test.
            for await _ in stream { count += 1 }
            return count
        }

        interactor = nil

        let count = await collector.value
        #expect(count >= 1)
    }

    @Test("inProgress is false before any execution")
    func inProgressInitiallyFalse() {
        #expect(FakeDurationInteractor().inProgress == false)
    }
}

// MARK: - Subject interactor broadcast

@Suite("StrataSubjectInteractor broadcast")
struct StrataSubjectInteractorBroadcastTests {

    @Test("every subscriber receives every emission")
    func broadcastsToAllSubscribers() async {
        let interactor = FakeContinuousSubjectInteractor()

        func collectThree(_ stream: AsyncStream<Int>) -> Task<[Int], Never> {
            Task {
                var values: [Int] = []
                for await value in stream {
                    values.append(value)
                    if values.count >= 3 { break }
                }
                return values
            }
        }

        // Both subscriptions are opened before the trigger; `stream` does not replay.
        let first = collectThree(interactor.stream)
        let second = collectThree(interactor.stream)

        try? await Task.sleep(for: .milliseconds(20))
        interactor(1)

        let a = await first.value
        let b = await second.value

        #expect(a == [10, 11, 12])
        #expect(b == [10, 11, 12])
    }

    @Test("stream finishes when the interactor deallocates")
    func streamFinishesOnDeinit() async {
        var interactor: FakeContinuousSubjectInteractor? = FakeContinuousSubjectInteractor()
        let stream = interactor!.stream

        let collector = Task { () -> Bool in
            for await _ in stream { }
            return true   // only reachable once the stream finishes
        }

        interactor = nil

        #expect(await collector.value)
    }

    @Test("a subscriber that stops iterating is unregistered")
    func subscriberUnregistersOnTermination() async {
        let interactor = FakeContinuousSubjectInteractor()

        do {
            let stream = interactor.stream
            let task = Task {
                for await _ in stream { break }
            }
            try? await Task.sleep(for: .milliseconds(20))
            interactor(1)
            await task.value
        }

        // Give the termination handler a moment to run.
        try? await Task.sleep(for: .milliseconds(50))

        // A second subscriber still works, proving the registry is in a sane state.
        let task = Task { () -> Int? in
            for await value in interactor.stream { return value }
            return nil
        }
        try? await Task.sleep(for: .milliseconds(20))
        interactor(2)

        #expect(await task.value == 20)
    }
}

// MARK: - StrataException bridging

@Suite("StrataException error bridging")
struct StrataExceptionBridgingTests {

    /// Accepts the value as a plain `Error`, which is where the Foundation default would win
    /// if `StrataException` did not refine `LocalizedError`.
    private func describe(_ error: Error) -> String {
        error.localizedDescription
    }

    @Test("message survives being typed as any Error")
    func messageSurvivesErasureToError() {
        let error = FakeStrataException(message: "domain failure")

        #expect(describe(error) == "domain failure")
    }

    @Test("built-in exceptions bridge their message too")
    func builtInExceptionsBridge() {
        #expect(describe(StrataCancellationException()) == "Operation was cancelled")
        #expect(describe(StrataTimeoutException(duration: 2)).contains("2"))
    }
}
