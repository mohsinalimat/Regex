// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// A simple parser combinators implementation. See Grammar.swift for the actual
// regex grammar.

// MARK: - Parser

struct Parser<A> {
    private let run: (_ string: inout Substring) throws -> A?

    init(_ parse: @escaping (_ string: inout Substring) throws -> A?) {
        self.run = parse
    }
}

extension Parser {
    /// Parses the given string. Automatically rollbacks to the point before
    /// parsing started if error is encountered.
    func parse(_ string: inout Substring) throws -> A? {
        let stash = string
        do {
            guard let match = try run(&string) else {
                string = stash
                return nil
            }
            return match
        } catch {
            string = stash // Rollback to the index before parsing started
            throw error
        }
    }

    func parse(_ string: String) throws -> A? {
        var substring = string[...]
        let output = try run(&substring)
        return output
    }
}

struct ParserError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        return "\(message)"
    }
}

// MARK: - Parser (Predifined)

struct Parsers {}

extension Parsers {
    /// Matches the given string.
    static func literal(_ p: String) -> Parser<Void> {
        return Parser<Void> { str in
            guard str.hasPrefix(p) else {
                return nil
            }
            str.removeFirst(p.count)
            return ()
        }
    }

    /// Matches any character contained in the given string.
    static func literal(from string: String) -> Parser<Void> {
        char(where: string.contains).map { _ in () }
    }

    /// Matches any single character.
    static let char = Parser<Character> { str in
        guard let first = str.first else {
            return nil
        }
        str.removeFirst()
        return first
    }

    /// Matches the given character.
    static func char(_ c: Character) -> Parser<Character> {
        char(where: { $0 == c })
    }

    /// Matches a character if it satisfies the given predicate.
    static func char(where predicate: @escaping (Character) -> Bool) -> Parser<Character> {
        char.map { predicate($0) ? $0 : nil }
    }

    /// Matches a character if the given string doesn't contain it.
    static func char(excluding string: String) -> Parser<Character> {
        char(where: { !string.contains($0) })
    }

    /// Matches characters while the given string doesn't contain them.
    static func string(excluding string: String) -> Parser<String> {
        char(excluding: string).oneOrMore.map { String($0) }
    }

    /// Parsers a natural number or zero. Valid inputs: "0", "1", "10".
    static let number = digit.oneOrMore.map { Int(String($0)) }

    /// Matches a single digit.
    static let digit: Parser<Character> = char(where: CharacterSet.decimalDigits.contains)
}

extension Parser: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral where A == Void {
    // Unfortunately had to add these explicitly supposably because of the
    // conditional conformance limitations.
    typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    typealias UnicodeScalarLiteralType = StringLiteralType
    typealias StringLiteralType = String

    init(stringLiteral value: String) {
        self = Parsers.literal(value)
    }
}

// MARK: - Parser (Combinators)

/// Matches only if both of the given parsers produced a result.
func zip<A, B>(_ a: Parser<A>, _ b: Parser<B>) -> Parser<(A, B)> {
    return Parser<(A, B)> { str -> (A, B)? in
        guard let matchA = try a.parse(&str), let matchB = try b.parse(&str) else {
            return nil
        }
        return (matchA, matchB)
    }
}

func zip<A, B, C>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>
) -> Parser<(A, B, C)> {
    zip(a, zip(b, c))
        .map { a, bc in (a, bc.0, bc.1) }
}

func zip<A, B, C, D>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>
) -> Parser<(A, B, C, D)> {
    zip(a, zip(b, c, d))
        .map { a, bcd in (a, bcd.0, bcd.1, bcd.2) }
}

func zip<A, B, C, D, E>(
    _ a: Parser<A>,
    _ b: Parser<B>,
    _ c: Parser<C>,
    _ d: Parser<D>,
    _ e: Parser<E>
) -> Parser<(A, B, C, D, E)> {
    zip(a, zip(b, c, d, e))
        .map { a, bcde in (a, bcde.0, bcde.1, bcde.2, bcde.3) }
}

/// Returns the first match or `nil` if no matches are found.
func oneOf<A>(_ parsers: Parser<A>...) -> Parser<A> {
    precondition(!parsers.isEmpty)
    return Parser<A> { str -> A? in
        for parser in parsers {
            if let match = try parser.parse(&str) {
                return match
            }
        }
        return nil
    }
}

extension Parser {
    func map<B>(_ transform: @escaping (A) throws -> B?) -> Parser<B> {
        flatMap { match in
            Parser<B> { _ in try transform(match) }
        }
    }

    func flatMap<B>(_ transform: @escaping (A) -> Parser<B>) -> Parser<B> {
        Parser<B> { str -> B? in
            guard let matchA = try self.parse(&str) else {
                return nil
            }
            let parserB = transform(matchA)
            return try parserB.parse(&str)
        }
    }
}

// MARK: - Parser (Quantifiers)

extension Parser {

    /// Throws an error with the given message if the parser fails to produce a match.
    func required(_ message: String) -> Parser {
        Parser { str -> A? in
            guard let match = try self.parse(&str) else {
                throw ParserError(message)
            }
            return match
        }
    }

    /// Matches the given parser zero or one times. Parser<A> -> Parser<A?> tranformation.
    var optional: Parser<A?> {
        Parser<A?> { str -> A?? in // yes, double-optional, zip unwraps it
            try self.parse(&str)
        }
    }

    /// Matches the given parser zero or more times.
    var zeroOrMore: Parser<[A]> {
        Parser<[A]> { str -> [A]? in
            var matches = [A]()
            while let match = try self.parse(&str) {
                matches.append(match)
            }
            return matches
        }
    }

    /// Matches the given parser one or more times.
    var oneOrMore: Parser<[A]> {
        zeroOrMore.map { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Parser (Misc)

extension Parsers {

    /// Succeeds when input is empty.
    static let end = Parser<Void> { str in str.isEmpty ? () : nil }

    /// Delays the creation of parser. Use it to break dependency cycles when
    /// creating recursive parsers.
    static func lazy<A>(_ closure: @autoclosure @escaping () -> Parser<A>) -> Parser<A> {
        Parser { str in
            try closure().parse(&str)
        }
    }
}
