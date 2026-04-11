//
//  CollectionShuffle.swift
//  Cinechill_iOS
//

import Foundation

enum CollectionShuffle {
    /// Fisher–Yates (même logique que le front web).
    nonisolated static func fisherYates<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0 ... i)
            if i != j {
                items.swapAt(i, j)
            }
        }
    }

    nonisolated static func shuffledCopy<T>(_ items: [T]) -> [T] {
        var copy = items
        fisherYates(&copy)
        return copy
    }
}
