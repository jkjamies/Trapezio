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

import XCTest

/// End-to-end coverage of the wiring no unit test reaches: `TrapezioNavigationHost` driving a
/// real `NavigationStack`, `TrapezioContainer` owning stores across pushes and pops, and
/// `TrapezioRuntime` routing events and lifecycle.
///
/// Deliberately asserts on behaviour rather than layout, so these do not break on styling changes.
final class CounterUITests: XCTestCase {

    private var app: XCUIApplication!

    private var timeout: TimeInterval { 10 }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func countLabel() -> XCUIElement {
        app.staticTexts["countLabel"]
    }

    private func waitForCount(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = expectation(
            for: NSPredicate(format: "label == %@", value),
            evaluatedWith: countLabel(),
            handler: nil
        )
        let result = XCTWaiter.wait(for: [matched], timeout: timeout)
        XCTAssertEqual(result, .completed, "count never reached \(value)", file: file, line: line)
    }

    // MARK: - Counter

    func test_launch_showsCounterAtInitialValue() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))
        XCTAssertEqual(countLabel().label, "0")
    }

    func test_incrementAndDecrement_updateTheRenderedState() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        app.buttons["incrementButton"].tap()
        app.buttons["incrementButton"].tap()
        waitForCount("2")

        app.buttons["decrementButton"].tap()
        waitForCount("1")
    }

    /// Exercises `launch(snapshot:work:reduce:)` end to end: snapshot on the main actor, work
    /// detached, reduce back on the main actor and into the rendered view.
    func test_divide_roundTripsThroughDetachedWork() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        for _ in 0..<8 {
            app.buttons["incrementButton"].tap()
        }
        waitForCount("8")

        app.buttons["divideButton"].tap()
        waitForCount("4")
    }

    // MARK: - Messages

    /// The message queue is bound in `onFirstAppear`. If that binding never ran, no message
    /// would ever reach state.
    func test_errorMessage_appearsAndDismisses() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        app.buttons["errorButton"].tap()

        let message = app.staticTexts["messageLabel"]
        XCTAssertTrue(message.waitForExistence(timeout: timeout))
        XCTAssertEqual(message.label, "Simulated Failure")

        app.buttons["dismissMessageButton"].tap()

        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: message,
            handler: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed)
    }

    // MARK: - Navigation

    func test_pushAndPop_preserveCounterState() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        app.buttons["incrementButton"].tap()
        app.buttons["incrementButton"].tap()
        app.buttons["incrementButton"].tap()
        waitForCount("3")

        app.buttons["goToSummaryButton"].tap()

        let summaryValue = app.staticTexts["summaryValueLabel"]
        XCTAssertTrue(summaryValue.waitForExistence(timeout: timeout))
        XCTAssertEqual(summaryValue.label, "3", "the pushed screen should carry the counter value")

        app.buttons["backButton"].tap()

        // The counter store must have survived the push and pop — a rebuilt store would show 0.
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))
        XCTAssertEqual(countLabel().label, "3")
    }

    /// A single Back must return to the counter. If `goTo` had pushed twice, it would not.
    func test_repeatedNavigationTaps_pushOnlyOneScreen() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        let goToSummary = app.buttons["goToSummaryButton"]
        goToSummary.tap()
        // A second tap while the destination is still settling must not enqueue another push.
        if goToSummary.exists && goToSummary.isHittable {
            goToSummary.tap()
        }

        XCTAssertTrue(app.staticTexts["summaryValueLabel"].waitForExistence(timeout: timeout))

        app.buttons["backButton"].tap()

        XCTAssertTrue(
            countLabel().waitForExistence(timeout: timeout),
            "one Back did not return to the counter — the destination was pushed more than once"
        )
    }

    // MARK: - Persistence

    /// Covers the full Strata round trip: store to interactor to `ModelActor` repository, then
    /// back through the observation stream bound in `onFirstAppear` and into state.
    func test_save_persistsAndFlowsBackThroughTheObservationStream() {
        XCTAssertTrue(countLabel().waitForExistence(timeout: timeout))

        app.buttons["incrementButton"].tap()
        waitForCount("1")

        app.buttons["goToSummaryButton"].tap()
        XCTAssertTrue(app.staticTexts["summaryValueLabel"].waitForExistence(timeout: timeout))

        app.buttons["saveButton"].tap()

        let saveMessage = app.staticTexts["saveMessageLabel"]
        XCTAssertTrue(saveMessage.waitForExistence(timeout: timeout))
        XCTAssertEqual(saveMessage.label, "Value saved successfully.")

        // The saved value arrives via the repository's stream, not from the save call's result.
        // Waited on by predicate rather than asserted directly: the SwiftData store survives
        // between runs, so a stale label may already be on screen when this test starts.
        let lastSaved = app.staticTexts["lastSavedLabel"]
        let updated = expectation(
            for: NSPredicate(format: "label == %@", "Last Saved: 1"),
            evaluatedWith: lastSaved,
            handler: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [updated], timeout: timeout), .completed,
            "the saved value never came back through the observation stream"
        )
    }
}
