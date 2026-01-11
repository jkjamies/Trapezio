//
//  CounterScreen.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import Trapezio

/// The "Parcelable" ID.
/// In a full system, this would be passed around by the Navigator.
struct CounterScreen: TrapezioScreen {
    let initialValue: Int
}

/// The Model.
struct CounterState: TrapezioState {
    var count: Int
    var isSaving: Bool = false
}

/// The Actions.
enum CounterEvent: TrapezioEvent {
    case increment
    case decrement
    case divideByTwo // example of usecase
    case goToSummary
}
