//
//  SummaryUi.swift
//  TrapezioCounter
//
//  Created by Jason Jamieson on 1/11/26.
//

import SwiftUI
import Trapezio

struct SummaryUI: TrapezioUI {
    func map(state: SummaryState, onEvent: @escaping (SummaryEvent) -> Void) -> some View {
        VStack(spacing: 30) {
            Text("Summary")
                .font(.title.bold())

            Text("\(state.value)")
                .font(.system(size: 60, weight: .bold, design: .monospaced))

            HStack(spacing: 16) {
                Button("Back") {
                    onEvent(.back)
                }
                .buttonStyle(.bordered)

                Button("Print Current Value") {
                    onEvent(.printValue)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
