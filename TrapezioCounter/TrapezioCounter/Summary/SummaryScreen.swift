//
//  SummaryScreen.swift
//  TrapezioCounter
//
//  Created by Jason Jamieson on 1/11/26.
//

import Trapezio

/// A secondary screen to demonstrate navigation interoperability.
struct SummaryScreen: TrapezioScreen {
    let value: Int
}

struct SummaryState: TrapezioState {
    let value: Int
}

enum SummaryEvent: TrapezioEvent {
    case printValue
    case back
}
