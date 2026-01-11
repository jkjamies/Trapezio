//
//  DivideUseCase.swift
//  Trapezio
//
//  Created by Jason Jamieson on 1/10/26.
//

import Foundation

public protocol DivideUsecaseProtocol: Sendable {
    func execute(value: Int) async -> Int
}

public struct DivideUsecase: DivideUsecaseProtocol {
    nonisolated public init() {}
    
    nonisolated public func execute(value: Int) async -> Int {
        try? await Task.sleep(nanoseconds: 100_000_000)
        return value / 2
    }
}
