//
//  ContentView.swift
//  TrapezioCounter
//
//  Created by Jason Jamieson on 1/10/26.
//

import SwiftUI
import Trapezio

struct ContentView: View {
    var body: some View {
        TrapezioNavigationHost(root: CounterScreen(initialValue: 0)) { screen, navigator in
            switch screen {
            case let counter as CounterScreen:
                CounterFactory.make(screen: counter, navigator: navigator)
            case let summary as SummaryScreen:
                SummaryFactory.make(screen: summary, navigator: navigator)
            default:
                EmptyView()
            }
        }
    }
}

#Preview {
    TrapezioNavigationHost(root: CounterScreen(initialValue: 99)) { screen, navigator in
        switch screen {
        case let counter as CounterScreen:
            CounterFactory.make(screen: counter, navigator: navigator)
        case let summary as SummaryScreen:
            SummaryFactory.make(screen: summary, navigator: navigator)
        default:
            EmptyView()
        }
    }
}
