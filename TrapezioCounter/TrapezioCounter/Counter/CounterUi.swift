//
//  CounterUi.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import SwiftUI
import Trapezio

struct CounterUI: TrapezioUI {
    func map(state: CounterState, onEvent: @escaping (CounterEvent) -> Void) -> some View {
        VStack(spacing: 30) {
            Text("\(state.count)")
                .font(.system(size: 60, weight: .bold, design: .monospaced))
            
            HStack(spacing: 20) {
                Button("-") { onEvent(.decrement) }
                    .buttonStyle(.bordered)
                
                Button("÷2") { onEvent(.divideByTwo) }
                    .buttonStyle(.borderedProminent)
                
                Button("+") { onEvent(.increment) }
                    .buttonStyle(.bordered)
            }
            
            Divider().padding(.horizontal)

            Button("Go To Summary") {
                onEvent(.goToSummary)
            }
            .font(.headline)
        }
        .padding()
    }
}
