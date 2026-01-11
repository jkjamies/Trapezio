//
//  SummaryFactory.swift
//  TrapezioCounter
//
//  Created by Jason Jamieson on 1/11/26.
//

import SwiftUI
import Trapezio

struct SummaryFactory {
    @ViewBuilder
    static func make(screen: SummaryScreen, navigator: (any TrapezioNavigator)?) -> some View {
        TrapezioContainer(
            makeStore: SummaryStore(screen: screen, navigator: navigator),
            ui: SummaryUI()
        )
    }
}
