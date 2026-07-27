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

import SwiftUI
import Trapezio
import TrapezioNavigation

struct CounterUI: TrapezioUI {
    func map(state: CounterState, onEvent: @escaping @MainActor (CounterEvent) -> Void) -> some View {
        VStack(spacing: 30) {
            Text("\(state.count)")
                .font(.system(size: 60, weight: .bold, design: .monospaced))
                .accessibilityIdentifier("countLabel")
            
            HStack(spacing: 20) {
                Button("-") { onEvent(.decrement) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("decrementButton")
                
                Button("÷2") { onEvent(.divideByTwo) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("divideButton")
                
                Button("+") { onEvent(.increment) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("incrementButton")
            }



            HStack {
                Button("Help") { onEvent(.requestHelp) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("helpButton")

                Button("Error") { onEvent(.throwError) }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("errorButton")
            }
            
            Divider().padding(.horizontal)

            Button("Go To Summary") {
                onEvent(.goToSummary)
            }
            .accessibilityIdentifier("goToSummaryButton")
            .font(.headline)
        }

        .padding()
        .overlay(alignment: .bottom) {
            if let msg = state.message {
                VStack {
                    Text(msg.message)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .accessibilityIdentifier("messageLabel")
                    Button("Dismiss") {
                        onEvent(.clearError(id: msg.id))
                    }
                    .accessibilityIdentifier("dismissMessageButton")
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding()
            }
        }
    }
}
