//
//  CounterFactory.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import SwiftUI
import Trapezio

struct CounterFactory {
    @ViewBuilder
    static func make(screen: CounterScreen, navigator: (any TrapezioNavigator)?) -> some View {
        // This line is what DI code essentially does:
        // Look at dependency graph and provide the real impl.
        let usecase = DivideUsecase()
        
        TrapezioContainer(
            makeStore: CounterStore(screen: screen, divideUsecase: usecase, navigator: navigator),
            ui: CounterUI()
        )
    }
}
