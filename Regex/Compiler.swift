// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Compiler {
    private let parser: Parser
    private let options: Regex.Options
    private var symbols: Symbols
    private var captureGroups: [CaptureGroup] = []
    private var backreferences: [ASTUnit.Backreference] = []

    init(_ pattern: String, _ options: Regex.Options) {
        self.parser = Parser(pattern, options)
        self.options = options
        self.symbols = Symbols()
    }

    func compile() throws -> (CompiledRegex, Symbols) {
        let ast = try parser.parse()
        guard ast.value.unit is ASTUnit.Root else {
            fatalError("Parser returned an invalid root node")
        }
        guard !ast.children.isEmpty else {
            throw Regex.Error("Pattern must not be empty", 0)
        }

        let expression = try compile(ast)

        try validateBackreferences()

        // TODO: remove this workaround
        // Wrap the expression into an implicit group. We do this as a workaround
        // to make sure Matcher registers all matches.
        let group = Expression.group(expression)

        return (CompiledRegex(expression: group, captureGroups: captureGroups), symbols)
    }
}

private extension Compiler {
    func compile(_ node: ASTNode) throws -> Expression {
        let expression = try _compile(node)
        symbols.map[expression.start] = node
        symbols.map[expression.end] = node
        return expression
    }

    func _compile(_ node: ASTNode) throws -> Expression {
        switch node.value.unit {
        case is ASTUnit.Root,
             is ASTUnit.Expression:
            let expressions = try node.children.map(compile)
            return .concatenate(expressions)

        case (let group as ASTUnit.Group):
            let expressions = try node.children.map(compile)
            let expression = Expression.group(.concatenate(expressions))
            if group.isCapturing { // Remember the group that we just compiled.
                captureGroups.append(CaptureGroup(index: group.index, start: expression.start, end: expression.end))
            }
            return expression

        case (let backreference as ASTUnit.Backreference):
            assert(node.children.isEmpty, "Backreferences must not have children")
            backreferences.append(backreference)
            return .backreference(backreference.index)

        case is ASTUnit.Alternation:
            let expressions = try node.children.map(compile)
            return .alternate(expressions)

        case (let anchor as ASTUnit.Anchor):
            assert(node.children.isEmpty, "Anchor must not have children")
            switch anchor {
            case .startOfString: return .startOfString
            case .startOfStringOnly: return .startOfStringOnly
            case .endOfString: return .endOfString
            case .endOfStringOnly: return .endOfStringOnly
            case .endOfStringOnlyNotNewline: return .endOfStringOnlyNotNewline
            case .wordBoundary: return .wordBoundary
            case .nonWordBoundary: return .nonWordBoundary
            case .previousMatchEnd: return .previousMatchEnd
            }

        case (let quantifier as ASTUnit.Quantifier):
            assert(node.children.count == 1, "Quantifier can only be applied to a single child")
            let expression = try compile(node.children[0])
            switch quantifier {
            case .zeroOrMore: return .zeroOrMore(expression)
            case .oneOrMore: return .oneOrMore(expression)
            case .zeroOrOne: return .zeroOrOne(expression)
            case let .range(range): return try compile(node, range)
            }

        case (let match as ASTUnit.Match):
            assert(node.children.isEmpty, "Match must not have children")
            switch match {
            case let .character(c): return .character(c)
            case let .anyCharacter(includingNewline): return .anyCharacter(includingNewline: includingNewline)
            case let .characterSet(set): return .characterSet(set)
            }

        default:
            fatalError("Unsupported unit \(node.value)")
        }
    }

    func compile(_ node: ASTNode, _ range: ClosedRange<Int>) throws -> Expression {
        let prefix: Expression = try .concatenate((0..<range.lowerBound).map { _ in
            try compile(node.children[0])
        })
        let suffix: Expression
        if range.upperBound == Int.max {
            suffix = .zeroOrOne(try compile(node.children[0]))
        } else {
            // Compile the optional matches into `x(x(x(x)?)?)?`. We use this
            // specific form with grouping to make sure that matcher can cache
            // the results during backtracking.
            suffix = try range.dropLast().reduce(Expression.empty) { result, _ in
                let expression = try compile(node.children[0])
                return .zeroOrOne(.group(.concatenate(expression, result)))
            }
        }
        return Expression.concatenate(prefix, suffix)
    }

    func validateBackreferences() throws {
        for backreference in backreferences {
            // TODO: move validation to parser?
            guard captureGroups.contains(where: { $0.index == backreference.index }) else {
                throw Regex.Error("The token '\\\(backreference.index)' references a non-existent or invalid subpattern", 0)
            }
        }
    }
}

// MARK: - CompiledRegex

struct CompiledRegex {
    /// The starting index in the compiled regular expression.
    let expression: Expression

    /// All the capture groups with their indexes.
    let captureGroups: [CaptureGroup]
}

struct CaptureGroup {
    let index: Int
    let start: State
    let end: State
}

// MARK: - Symbols

/// Mapping between states of the finite state machine and the nodes for which
/// they were produced.
struct Symbols {
    fileprivate(set) var map = [State: ASTNode]()
}
