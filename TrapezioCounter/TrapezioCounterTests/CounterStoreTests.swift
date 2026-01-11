//
//  CounterStoreTests.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import XCTest
import Trapezio
@testable import TrapezioCounter

@MainActor
final class CounterStoreTests: XCTestCase {
    
    var store: CounterStore!
    
    override func setUp() {
        super.setUp()
        
        // 2. Manual Injection: We provide the fake directly.
        // This is where we "simulate" a DI override.
        let screen = CounterScreen(initialValue: 10)
        let fakeUsecase = FakeDivideUsecase()
        
        store = CounterStore(
            screen: screen,
            divideUsecase: fakeUsecase,
            navigator: nil
        )
    }

    func test_increment_increasesCount() {
        store.handle(event: .increment)
        XCTAssertEqual(store.state.count, 11)
    }

    func test_decrement_decreasesCount() {
        store.handle(event: .decrement)
        XCTAssertEqual(store.state.count, 9)
    }

    func test_goToSummary_withNilNavigator_doesNotMutateState() {
        let initialCount = store.state.count
        store.handle(event: .goToSummary)
        XCTAssertEqual(store.state.count, initialCount)
    }

    func test_divideByTwo_isInstantAndDeterministic() async {
        store.handle(event: .divideByTwo)
        // No more long sleep!
        // Use yield to let the Store's Task { } block start and finish.
        await Task.yield()
        XCTAssertEqual(store.state.count, 5, "The count should be divided by 2 instantly using the fake.")
    }
}
