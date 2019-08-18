// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import Foundation
import os.log

// MARK: - CharacterSet

extension CharacterSet {
    // Analog of '\w' (word set)
    static let word = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_"))

    /// Insert all the individual unicode scalars which the character
    /// consists of.
    mutating func insert(_ c: Character) {
        for scalar in c.unicodeScalars {
            insert(scalar)
        }
    }

    /// Returns true if all of the unicode scalars in the given character
    /// are in the characer set.
    func contains(_ c: Character) -> Bool {
        return c.unicodeScalars.allSatisfy(contains)
    }
}

// MARK: - Character

extension Character {
    // Returns `true` if the character belong to "word" category ('\w')
    var isWord: Bool {
        return CharacterSet.word.contains(self)
    }
}

// MARK: - Range

extension Range where Bound == Int {
    /// Returns the range which contains the indexes from both ranges and
    /// everything in between.
    static func merge(_ lhs: Range, _ rhs: Range) -> Range {
        return (Swift.min(lhs.lowerBound, rhs.lowerBound))..<(Swift.max(lhs.upperBound, rhs.upperBound))
    }
}

// MARK: - String

extension String {
    /// Returns a substring with the given range. The indexes are automatically
    /// calculated by offsetting the existing indexes.
    func substring(_ range: Range<Int>) -> Substring {
        return self[index(startIndex, offsetBy: range.lowerBound)..<index(startIndex, offsetBy: range.upperBound)]
    }
}

extension Substring {
    /// Returns a substring with the given range. The indexes are automatically
    /// calculated by offsetting the existing indexes.
    func substring(_ range: Range<Int>) -> Substring {
        return self[index(startIndex, offsetBy: range.lowerBound)..<index(startIndex, offsetBy: range.upperBound)]
    }

    func offset(for index: String.Index) -> Int {
        return distance(from: startIndex, to: index)
    }
}

// MARK: - OSLog

extension OSLog {
    // Returns `true` if the default logging type enabled.
    var isEnabled: Bool {
        return isEnabled(type: .default)
    }
}
