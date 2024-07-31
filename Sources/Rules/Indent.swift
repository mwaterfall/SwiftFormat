//
//  Indent.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 8/22/16.
//  Copyright © 2024 Nick Lockwood. All rights reserved.
//

import Foundation

public extension FormatRule {
    /// Indent code according to standard scope indenting rules.
    /// The type (tab or space) and level (2 spaces, 4 spaces, etc.) of the
    /// indenting can be configured with the `options` parameter of the formatter.
    static let indent = FormatRule(
        help: "Indent code in accordance with the scope level.",
        orderAfter: [.trailingSpace, .wrap, .wrapArguments],
        options: ["indent", "tabwidth", "smarttabs", "indentcase", "ifdef", "xcodeindentation", "indentstrings"],
        sharedOptions: ["trimwhitespace", "allman", "wrapconditions", "wrapternary"]
    ) { formatter in
        var scopeStack: [Token] = []
        var scopeStartLineIndexes: [Int] = []
        var lastNonSpaceOrLinebreakIndex = -1
        var lastNonSpaceIndex = -1
        var indentStack = [""]
        var stringBodyIndentStack = [""]
        var indentCounts = [1]
        var linewrapStack = [false]
        var lineIndex = 0

        func inFunctionDeclarationWhereReturnTypeIsWrappedToStartOfLine(at i: Int) -> Bool {
            guard let returnOperatorIndex = formatter.startOfReturnType(at: i) else {
                return false
            }
            return formatter.last(.nonSpaceOrComment, before: returnOperatorIndex)?.isLinebreak == true
        }

        func isFirstStackedClosureArgument(at i: Int) -> Bool {
            assert(formatter.tokens[i] == .startOfScope("{"))
            if let prevIndex = formatter.index(of: .nonSpace, before: i),
               let prevToken = formatter.token(at: prevIndex), prevToken == .startOfScope("(") ||
               (prevToken == .delimiter(":") && formatter.token(at: prevIndex - 1)?.isIdentifier == true
                   && formatter.last(.nonSpace, before: prevIndex - 1) == .startOfScope("(")),
               let endIndex = formatter.endOfScope(at: i),
               let commaIndex = formatter.index(of: .nonSpace, after: endIndex, if: {
                   $0 == .delimiter(",")
               }),
               formatter.next(.nonSpaceOrComment, after: commaIndex)?.isLinebreak == true
            {
                return true
            }
            return false
        }

        if formatter.options.fragment,
           let firstIndex = formatter.index(of: .nonSpaceOrLinebreak, after: -1),
           let indentToken = formatter.token(at: firstIndex - 1), case let .space(string) = indentToken
        {
            indentStack[0] = string
        }
        formatter.forEachToken(onlyWhereEnabled: false) { i, token in
            func popScope() {
                if linewrapStack.last == true {
                    indentStack.removeLast()
                    stringBodyIndentStack.removeLast()
                }
                indentStack.removeLast()
                stringBodyIndentStack.removeLast()
                indentCounts.removeLast()
                linewrapStack.removeLast()
                scopeStartLineIndexes.removeLast()
                scopeStack.removeLast()
            }

            func stringBodyIndent(at i: Int) -> String {
                var space = ""
                let start = formatter.startOfLine(at: i)
                if let index = formatter.index(of: .nonSpace, in: start ..< i),
                   case let .stringBody(string) = formatter.tokens[index],
                   string.unicodeScalars.first?.isSpace == true
                {
                    var index = string.startIndex
                    while index < string.endIndex, string[index].unicodeScalars.first!.isSpace {
                        space.append(string[index])
                        index = string.index(after: index)
                    }
                }
                return space
            }

            var i = i
            switch token {
            case let .startOfScope(string):
                switch string {
                case ":" where scopeStack.last == .endOfScope("case"):
                    popScope()
                case "{" where !formatter.isStartOfClosure(at: i, in: scopeStack.last) &&
                    linewrapStack.last == true:
                    indentStack.removeLast()
                    linewrapStack[linewrapStack.count - 1] = false
                default:
                    break
                }
                // Handle start of scope
                scopeStack.append(token)
                var indentCount: Int
                if lineIndex > scopeStartLineIndexes.last ?? -1 {
                    indentCount = 1
                } else if token.isMultilineStringDelimiter, let endIndex = formatter.endOfScope(at: i),
                          let closingIndex = formatter.index(of: .endOfScope(")"), after: endIndex),
                          formatter.next(.linebreak, in: endIndex + 1 ..< closingIndex) != nil
                {
                    indentCount = 1
                } else if scopeStack.count > 1, scopeStack[scopeStack.count - 2] == .startOfScope(":") {
                    indentCount = 1
                } else {
                    indentCount = indentCounts.last! + 1
                }
                var indent = indentStack[indentStack.count - indentCount]

                switch string {
                case "/*":
                    if scopeStack.count < 2 || scopeStack[scopeStack.count - 2] != .startOfScope("/*") {
                        // Comments only indent one space
                        indent += " "
                    }
                case ":":
                    indent += formatter.options.indent
                    if formatter.options.indentCase,
                       scopeStack.count < 2 || scopeStack[scopeStack.count - 2] != .startOfScope("#if")
                    {
                        indent += formatter.options.indent
                    }
                case "#if":
                    if let lineIndex = formatter.index(of: .linebreak, after: i),
                       let nextKeyword = formatter.next(.nonSpaceOrCommentOrLinebreak, after: lineIndex), [
                           .endOfScope("case"), .endOfScope("default"), .keyword("@unknown"),
                       ].contains(nextKeyword)
                    {
                        indent = indentStack[indentStack.count - indentCount - 1]
                        if formatter.options.indentCase {
                            indent += formatter.options.indent
                        }
                    }
                    switch formatter.options.ifdefIndent {
                    case .indent:
                        i += formatter.insertSpaceIfEnabled(indent, at: formatter.startOfLine(at: i))
                        indent += formatter.options.indent
                    case .noIndent:
                        i += formatter.insertSpaceIfEnabled(indent, at: formatter.startOfLine(at: i))
                    case .outdent:
                        i += formatter.insertSpaceIfEnabled("", at: formatter.startOfLine(at: i))
                    }
                case "{" where isFirstStackedClosureArgument(at: i):
                    guard var prevIndex = formatter.index(of: .nonSpace, before: i) else {
                        assertionFailure()
                        break
                    }
                    if formatter.tokens[prevIndex] == .delimiter(":") {
                        guard formatter.token(at: prevIndex - 1)?.isIdentifier == true,
                              let parenIndex = formatter.index(of: .nonSpace, before: prevIndex - 1, if: {
                                  $0 == .startOfScope("(")
                              })
                        else {
                            let stringIndent = stringBodyIndent(at: i)
                            stringBodyIndentStack[stringBodyIndentStack.count - 1] = stringIndent
                            indent += stringIndent + formatter.options.indent
                            break
                        }
                        prevIndex = parenIndex
                    }
                    let startIndex = formatter.startOfLine(at: i)
                    indent = formatter.spaceEquivalentToTokens(from: startIndex, upTo: prevIndex + 1)
                    indentStack[indentStack.count - 1] = indent
                    indent += formatter.options.indent
                    indentCount -= 1
                case "{" where formatter.isStartOfClosure(at: i):
                    // When a trailing closure starts on the same line as the end of a multi-line
                    // method call the trailing closure body should be double-indented
                    if let prevIndex = formatter.index(of: .nonSpaceOrComment, before: i),
                       formatter.tokens[prevIndex] == .endOfScope(")"),
                       case let prevIndent = formatter.currentIndentForLine(at: prevIndex),
                       prevIndent == indent + formatter.options.indent
                    {
                        if linewrapStack.last == false {
                            linewrapStack[linewrapStack.count - 1] = true
                            indentStack.append(prevIndent)
                            stringBodyIndentStack.append("")
                        }
                        indent = prevIndent
                    }
                    let stringIndent = stringBodyIndent(at: i)
                    stringBodyIndentStack[stringBodyIndentStack.count - 1] = stringIndent
                    indent += stringIndent + formatter.options.indent
                case _ where token.isStringDelimiter, "//":
                    break
                case "[", "(":
                    guard let linebreakIndex = formatter.index(of: .linebreak, after: i),
                          let nextIndex = formatter.index(of: .nonSpace, after: i),
                          nextIndex != linebreakIndex
                    else {
                        fallthrough
                    }
                    if formatter.last(.nonSpaceOrComment, before: linebreakIndex) != .delimiter(","),
                       formatter.next(.nonSpaceOrComment, after: linebreakIndex) != .delimiter(",")
                    {
                        fallthrough
                    }
                    let start = formatter.startOfLine(at: i)
                    // Align indent with previous value
                    let lastIndentCount = indentCounts.last ?? 0
                    if indentCount > lastIndentCount {
                        indentCount = lastIndentCount
                        indentCounts[indentCounts.count - 1] = 1
                    }
                    indent = formatter.spaceEquivalentToTokens(from: start, upTo: nextIndex)
                default:
                    let stringIndent = stringBodyIndent(at: i)
                    stringBodyIndentStack[stringBodyIndentStack.count - 1] = stringIndent
                    indent += stringIndent + formatter.options.indent
                }
                indentStack.append(indent)
                stringBodyIndentStack.append("")
                indentCounts.append(indentCount)
                scopeStartLineIndexes.append(lineIndex)
                linewrapStack.append(false)
            case .space:
                if i == 0, !formatter.options.fragment,
                   formatter.token(at: i + 1)?.isLinebreak != true
                {
                    formatter.removeToken(at: i)
                }
            case .error("}"), .error("]"), .error(")"), .error(">"):
                // Handled over-terminated fragment
                if let prevToken = formatter.token(at: i - 1) {
                    if case let .space(string) = prevToken {
                        let prevButOneToken = formatter.token(at: i - 2)
                        if prevButOneToken == nil || prevButOneToken!.isLinebreak {
                            indentStack[0] = string
                        }
                    } else if prevToken.isLinebreak {
                        indentStack[0] = ""
                    }
                }
                return
            case .keyword("#else"), .keyword("#elseif"):
                var indent = indentStack[indentStack.count - 2]
                if scopeStack.last == .startOfScope(":") {
                    indent = indentStack[indentStack.count - 4]
                    if formatter.options.indentCase {
                        indent += formatter.options.indent
                    }
                }
                let start = formatter.startOfLine(at: i)
                switch formatter.options.ifdefIndent {
                case .indent, .noIndent:
                    i += formatter.insertSpaceIfEnabled(indent, at: start)
                case .outdent:
                    i += formatter.insertSpaceIfEnabled("", at: start)
                }
            case .keyword("@unknown") where scopeStack.last != .startOfScope("#if"):
                var indent = indentStack[indentStack.count - 2]
                if formatter.options.indentCase {
                    indent += formatter.options.indent
                }
                let start = formatter.startOfLine(at: i)
                let stringIndent = stringBodyIndentStack.last!
                i += formatter.insertSpaceIfEnabled(stringIndent + indent, at: start)
            case .keyword("in") where scopeStack.last == .startOfScope("{"):
                if let startIndex = formatter.index(of: .startOfScope("{"), before: i),
                   formatter.index(of: .keyword("for"), in: startIndex + 1 ..< i) == nil,
                   let paramsIndex = formatter.index(of: .startOfScope, in: startIndex + 1 ..< i),
                   !formatter.tokens[startIndex + 1 ..< paramsIndex].contains(where: {
                       $0.isLinebreak
                   }), formatter.tokens[paramsIndex + 1 ..< i].contains(where: {
                       $0.isLinebreak
                   })
                {
                    indentStack[indentStack.count - 1] += formatter.options.indent
                }
            case .operator("=", .infix):
                // If/switch expressions on their own line following an `=` assignment should always be indented
                guard let nextKeyword = formatter.index(of: .nonSpaceOrCommentOrLinebreak, after: i),
                      ["if", "switch"].contains(formatter.tokens[nextKeyword].string),
                      !formatter.onSameLine(i, nextKeyword)
                else { fallthrough }

                let indent = (indentStack.last ?? "") + formatter.options.indent
                indentStack.append(indent)
                stringBodyIndentStack.append("")
                indentCounts.append(1)
                scopeStartLineIndexes.append(lineIndex)
                linewrapStack.append(false)
                scopeStack.append(.operator("=", .infix))
                scopeStartLineIndexes.append(lineIndex)
            default:
                // If this is the final `endOfScope` in a conditional assignment,
                // we have to end the scope introduced by that assignment operator.
                defer {
                    if token == .endOfScope("}"), let startOfScope = formatter.startOfScope(at: i) {
                        // Find the `=` before this start of scope, which isn't itself part of the conditional statement
                        var previousAssignmentIndex = formatter.index(of: .operator("=", .infix), before: startOfScope)
                        while let currentPreviousAssignmentIndex = previousAssignmentIndex,
                              formatter.isConditionalStatement(at: currentPreviousAssignmentIndex)
                        {
                            previousAssignmentIndex = formatter.index(of: .operator("=", .infix), before: currentPreviousAssignmentIndex)
                        }

                        // Make sure the `=` actually created a new scope
                        if scopeStack.last == .operator("=", .infix),
                           // Parse the conditional branches following the `=` assignment operator
                           let previousAssignmentIndex = previousAssignmentIndex,
                           let nextTokenAfterAssignment = formatter.index(of: .nonSpaceOrCommentOrLinebreak, after: previousAssignmentIndex),
                           let conditionalBranches = formatter.conditionalBranches(at: nextTokenAfterAssignment),
                           // If this is the very end of the conditional assignment following the `=`,
                           // then we can end the scope.
                           conditionalBranches.last?.endOfBranch == i
                        {
                            popScope()
                        }
                    }
                }

                // Handle end of scope
                if let scope = scopeStack.last, token.isEndOfScope(scope) {
                    let indentCount = indentCounts.last! - 1
                    popScope()
                    guard !token.isLinebreak, lineIndex > scopeStartLineIndexes.last ?? -1 else {
                        break
                    }
                    // If indentCount > 0, drop back to previous indent level
                    if indentCount > 0 {
                        indentStack.removeLast(indentCount)
                        stringBodyIndentStack.removeLast(indentCount)
                        for _ in 0 ..< indentCount {
                            indentStack.append(indentStack.last ?? "")
                            stringBodyIndentStack.append(stringBodyIndentStack.last ?? "")
                        }
                    }

                    // Don't reduce indent if line doesn't start with end of scope
                    let start = formatter.startOfLine(at: i)
                    guard let firstIndex = formatter.index(of: .nonSpaceOrComment, after: start - 1) else {
                        break
                    }
                    if firstIndex != i {
                        break
                    }
                    func isInIfdef() -> Bool {
                        guard scopeStack.last == .startOfScope("#if") else {
                            return false
                        }
                        var index = i - 1
                        while index > 0 {
                            switch formatter.tokens[index] {
                            case .keyword("switch"):
                                return false
                            case .startOfScope("#if"), .keyword("#else"), .keyword("#elseif"):
                                return true
                            default:
                                index -= 1
                            }
                        }
                        return false
                    }
                    if token == .endOfScope("#endif"), formatter.options.ifdefIndent == .outdent {
                        i += formatter.insertSpaceIfEnabled("", at: start)
                    } else {
                        var indent = indentStack.last ?? ""
                        if token.isSwitchCaseOrDefault,
                           formatter.options.indentCase, !isInIfdef()
                        {
                            indent += formatter.options.indent
                        }
                        let stringIndent = stringBodyIndentStack.last!
                        i += formatter.insertSpaceIfEnabled(stringIndent + indent, at: start)
                    }
                } else if token == .endOfScope("#endif"), indentStack.count > 1 {
                    var indent = indentStack[indentStack.count - 2]
                    if scopeStack.last == .startOfScope(":"), indentStack.count > 1 {
                        indent = indentStack[indentStack.count - 4]
                        if formatter.options.indentCase {
                            indent += formatter.options.indent
                        }
                        popScope()
                    }
                    switch formatter.options.ifdefIndent {
                    case .indent, .noIndent:
                        i += formatter.insertSpaceIfEnabled(indent, at: formatter.startOfLine(at: i))
                    case .outdent:
                        i += formatter.insertSpaceIfEnabled("", at: formatter.startOfLine(at: i))
                    }
                    if scopeStack.last == .startOfScope("#if") {
                        popScope()
                    }
                }
            }
            switch token {
            case .endOfScope("case"):
                scopeStack.append(token)
                var indent = (indentStack.last ?? "")
                if formatter.next(.nonSpaceOrComment, after: i)?.isLinebreak == true {
                    indent += formatter.options.indent
                } else {
                    if formatter.options.indentCase {
                        indent += formatter.options.indent
                    }
                    // Align indent with previous case value
                    indent += formatter.spaceEquivalentToWidth(5)
                }
                indentStack.append(indent)
                stringBodyIndentStack.append("")
                indentCounts.append(1)
                scopeStartLineIndexes.append(lineIndex)
                linewrapStack.append(false)
                fallthrough
            case .endOfScope("default"), .keyword("@unknown"),
                 .startOfScope("#if"), .keyword("#else"), .keyword("#elseif"):
                var index = formatter.startOfLine(at: i)
                if index == i || index == i - 1 {
                    let indent: String
                    if case let .space(space) = formatter.tokens[index] {
                        indent = space
                    } else {
                        indent = ""
                    }
                    index -= 1
                    while let prevToken = formatter.token(at: index - 1), prevToken.isComment,
                          let startIndex = formatter.index(of: .nonSpaceOrComment, before: index),
                          formatter.tokens[startIndex].isLinebreak
                    {
                        // Set indent for comment immediately before this line to match this line
                        if !formatter.isCommentedCode(at: startIndex + 1) {
                            formatter.insertSpaceIfEnabled(indent, at: startIndex + 1)
                        }
                        if case .endOfScope("*/") = prevToken,
                           var index = formatter.index(of: .startOfScope("/*"), after: startIndex)
                        {
                            while let linebreakIndex = formatter.index(of: .linebreak, after: index) {
                                formatter.insertSpaceIfEnabled(indent + " ", at: linebreakIndex + 1)
                                index = linebreakIndex
                            }
                        }
                        index = startIndex
                    }
                }
            case .linebreak:
                // Detect linewrap
                let nextTokenIndex = formatter.index(of: .nonSpaceOrCommentOrLinebreak, after: i)
                let _nextToken = nextTokenIndex.map { formatter.tokens[$0] } ?? .space("")
                let linewrapped = lastNonSpaceOrLinebreakIndex > -1 && (
                    !formatter.isEndOfStatement(at: lastNonSpaceOrLinebreakIndex, in: scopeStack.last) ||
                        (nextTokenIndex.map { formatter.isTrailingClosureLabel(at: $0) } == true) ||
                        !(nextTokenIndex == nil || [
                            .endOfScope("}"), .endOfScope("]"), .endOfScope(")"),
                        ].contains(_nextToken) || _nextToken.isStringBody ||
                            formatter.isStartOfStatement(at: nextTokenIndex!, in: scopeStack.last) || (
                                ((_nextToken.isIdentifier && !(_nextToken == .identifier("async") && formatter.currentScope(at: nextTokenIndex!) != .startOfScope("("))) || [
                                    .keyword("try"), .keyword("await"),
                                ].contains(_nextToken)) &&
                                    formatter.last(.nonSpaceOrCommentOrLinebreak, before: nextTokenIndex!).map {
                                        $0 != .keyword("return") && !$0.isOperator(ofType: .infix)
                                    } ?? false) || (
                                _nextToken == .delimiter(",") && [
                                    "<", "[", "(", "case",
                                ].contains(formatter.currentScope(at: nextTokenIndex!)?.string ?? "")
                            )
                        )
                )

                // Determine current indent
                var indent = indentStack.last ?? ""
                if linewrapped, lineIndex == scopeStartLineIndexes.last {
                    indent = indentStack.count > 1 ? indentStack[indentStack.count - 2] : ""
                }
                lineIndex += 1

                func shouldIndentNextLine(at i: Int) -> Bool {
                    // If there is a linebreak after certain symbols, we should add
                    // an additional indentation to the lines at the same indention scope
                    // after this line.
                    let endOfLine = formatter.endOfLine(at: i)
                    switch formatter.token(at: endOfLine - 1) {
                    case .keyword("return")?, .operator("=", .infix)?:
                        let endOfNextLine = formatter.endOfLine(at: endOfLine + 1)
                        switch formatter.last(.nonSpaceOrCommentOrLinebreak, before: endOfNextLine) {
                        case .operator(_, .infix)?, .delimiter(",")?:
                            return false
                        case .endOfScope(")")?:
                            return !formatter.options.xcodeIndentation
                        default:
                            return formatter.lastIndex(of: .startOfScope,
                                                       in: i ..< endOfNextLine) == nil
                        }
                    default:
                        return false
                    }
                }

                guard var nextNonSpaceIndex = formatter.index(of: .nonSpace, after: i),
                      let nextToken = formatter.token(at: nextNonSpaceIndex)
                else {
                    break
                }

                // Begin wrap scope
                if linewrapStack.last == true {
                    if !linewrapped {
                        indentStack.removeLast()
                        linewrapStack[linewrapStack.count - 1] = false
                        indent = indentStack.last!
                    } else {
                        let shouldIndentLeadingDotStatement: Bool
                        if formatter.options.xcodeIndentation {
                            if let prevIndex = formatter.index(of: .nonSpaceOrCommentOrLinebreak, before: i),
                               formatter.token(at: formatter.startOfLine(
                                   at: prevIndex, excludingIndent: true
                               )) == .endOfScope("}"),
                               formatter.index(of: .linebreak, in: prevIndex + 1 ..< i) != nil
                            {
                                shouldIndentLeadingDotStatement = false
                            } else {
                                shouldIndentLeadingDotStatement = true
                            }
                        } else {
                            shouldIndentLeadingDotStatement = (
                                formatter.startOfConditionalStatement(at: i) != nil
                                    && formatter.options.wrapConditions == .beforeFirst
                            )
                        }
                        if shouldIndentLeadingDotStatement,
                           formatter.next(.nonSpace, after: i) == .operator(".", .infix),
                           let prevIndex = formatter.index(of: .nonSpaceOrCommentOrLinebreak, before: i),
                           case let lineStart = formatter.index(of: .linebreak, before: prevIndex + 1) ??
                           formatter.startOfLine(at: prevIndex),
                           let startIndex = formatter.index(of: .nonSpace, after: lineStart),
                           formatter.isStartOfStatement(at: startIndex) || (
                               (formatter.tokens[startIndex].isIdentifier || [
                                   .keyword("try"), .keyword("await"),
                               ].contains(formatter.tokens[startIndex]) ||
                                   formatter.isTrailingClosureLabel(at: startIndex)) &&
                                   formatter.last(.nonSpaceOrCommentOrLinebreak, before: startIndex).map {
                                       $0 != .keyword("return") && !$0.isOperator(ofType: .infix)
                                   } ?? false)
                        {
                            indent += formatter.options.indent
                            indentStack[indentStack.count - 1] = indent
                        }

                        // When inside conditionals, unindent after any commas (which separate conditions)
                        // that were indented by the block above
                        if !formatter.options.xcodeIndentation,
                           formatter.options.wrapConditions == .beforeFirst,
                           formatter.isConditionalStatement(at: i),
                           formatter.lastToken(before: i, where: {
                               $0.is(.nonSpaceOrCommentOrLinebreak)
                           }) == .delimiter(","),
                           let conditionBeginIndex = formatter.index(before: i, where: {
                               ["if", "guard", "while", "for"].contains($0.string)
                           }),
                           formatter.currentIndentForLine(at: conditionBeginIndex)
                           .count < indent.count + formatter.options.indent.count
                        {
                            indent = formatter.currentIndentForLine(at: conditionBeginIndex) + formatter.options.indent
                            indentStack[indentStack.count - 1] = indent
                        }

                        let startOfLineIndex = formatter.startOfLine(at: i, excludingIndent: true)
                        let startOfLine = formatter.tokens[startOfLineIndex]

                        if formatter.options.wrapTernaryOperators == .beforeOperators,
                           startOfLine == .operator(":", .infix) || startOfLine == .operator("?", .infix)
                        {
                            // Push a ? scope onto the stack so we can easily know
                            // that the next : is the closing operator of this ternary
                            if startOfLine.string == "?" {
                                // We smuggle the index of this operator in the scope stack
                                // so we can recover it trivially when handling the
                                // corresponding : operator.
                                scopeStack.append(.operator("?-\(startOfLineIndex)", .infix))
                            }

                            // Indent any operator-leading lines following a compomnent operator
                            // of a wrapped ternary operator expression, except for the :
                            // following a ?
                            if let nextToken = formatter.next(.nonSpace, after: i),
                               nextToken.isOperator(ofType: .infix),
                               nextToken != .operator(":", .infix)
                            {
                                indent += formatter.options.indent
                                indentStack[indentStack.count - 1] = indent
                            }
                        }

                        // Make sure the indentation for this : operator matches
                        // the indentation of the previous ? operator
                        if formatter.options.wrapTernaryOperators == .beforeOperators,
                           formatter.next(.nonSpace, after: i) == .operator(":", .infix),
                           let scope = scopeStack.last,
                           scope.string.hasPrefix("?"),
                           scope.isOperator(ofType: .infix),
                           let previousOperatorIndex = scope.string.components(separatedBy: "-").last.flatMap({ Int($0) })
                        {
                            scopeStack.removeLast()
                            indent = formatter.currentIndentForLine(at: previousOperatorIndex)
                            indentStack[indentStack.count - 1] = indent
                        }
                    }
                } else if linewrapped {
                    func isWrappedDeclaration() -> Bool {
                        guard let keywordIndex = formatter
                            .indexOfLastSignificantKeyword(at: i, excluding: [
                                "where", "throws", "rethrows",
                            ]), !formatter.tokens[keywordIndex ..< i].contains(.endOfScope("}")),
                            case let .keyword(keyword) = formatter.tokens[keywordIndex],
                            ["class", "actor", "struct", "enum", "protocol", "extension",
                             "func"].contains(keyword)
                        else {
                            return false
                        }

                        let end = formatter.endOfLine(at: i + 1)
                        guard let lastToken = formatter.last(.nonSpaceOrCommentOrLinebreak, before: end + 1),
                              [.startOfScope("{"), .endOfScope("}")].contains(lastToken) else { return false }

                        return true
                    }

                    // Don't indent line starting with dot if previous line was just a closing brace
                    var lastToken = formatter.tokens[lastNonSpaceOrLinebreakIndex]
                    if formatter.options.allmanBraces, nextToken == .startOfScope("{"),
                       formatter.isStartOfClosure(at: nextNonSpaceIndex)
                    {
                        // Don't indent further
                    } else if formatter.token(at: nextTokenIndex ?? -1) == .operator(".", .infix) ||
                        formatter.isLabel(at: nextTokenIndex ?? -1)
                    {
                        var lineStart = formatter.startOfLine(at: lastNonSpaceOrLinebreakIndex, excludingIndent: true)
                        let startToken = formatter.token(at: lineStart)
                        if let startToken = startToken, [
                            .startOfScope("#if"), .keyword("#else"), .keyword("#elseif"), .endOfScope("#endif")
                        ].contains(startToken) {
                            if let index = formatter.index(of: .nonSpaceOrCommentOrLinebreak, before: lineStart) {
                                lastNonSpaceOrLinebreakIndex = index
                                lineStart = formatter.startOfLine(at: lastNonSpaceOrLinebreakIndex, excludingIndent: true)
                            }
                        }
                        if formatter.token(at: lineStart) == .operator(".", .infix),
                           [.keyword("#else"), .keyword("#elseif"), .endOfScope("#endif")].contains(startToken)
                        {
                            indent = formatter.currentIndentForLine(at: lineStart)
                        } else if formatter.tokens[lineStart ..< lastNonSpaceOrLinebreakIndex].allSatisfy({
                            $0.isEndOfScope || $0.isSpaceOrComment
                        }) {
                            if lastToken.isEndOfScope {
                                indent = formatter.currentIndentForLine(at: lastNonSpaceOrLinebreakIndex)
                            }
                            if !lastToken.isEndOfScope || lastToken == .endOfScope("case") ||
                                formatter.options.xcodeIndentation, ![
                                    .endOfScope("}"), .endOfScope(")")
                                ].contains(lastToken)
                            {
                                indent += formatter.options.indent
                            }
                        } else if !formatter.options.xcodeIndentation || !isWrappedDeclaration() {
                            indent += formatter.linewrapIndent(at: i)
                        }
                    } else if !formatter.options.xcodeIndentation || !isWrappedDeclaration() {
                        indent += formatter.linewrapIndent(at: i)
                    }

                    linewrapStack[linewrapStack.count - 1] = true
                    indentStack.append(indent)
                    stringBodyIndentStack.append("")
                }
                // Avoid indenting commented code
                guard !formatter.isCommentedCode(at: nextNonSpaceIndex) else {
                    break
                }
                // Apply indent
                switch nextToken {
                case .linebreak:
                    if formatter.options.truncateBlankLines {
                        formatter.insertSpaceIfEnabled("", at: i + 1)
                    } else if scopeStack.last?.isStringDelimiter == true,
                              formatter.token(at: i + 1)?.isSpace == true
                    {
                        formatter.insertSpaceIfEnabled(indent, at: i + 1)
                    }
                case .error, .keyword("#else"), .keyword("#elseif"), .endOfScope("#endif"),
                     .startOfScope("#if") where formatter.options.ifdefIndent != .indent:
                    break
                case .startOfScope("/*"), .commentBody, .endOfScope("*/"):
                    nextNonSpaceIndex = formatter.endOfScope(at: nextNonSpaceIndex) ?? nextNonSpaceIndex
                    fallthrough
                case .startOfScope("//"):
                    nextNonSpaceIndex = formatter.index(of: .nonSpaceOrCommentOrLinebreak,
                                                        after: nextNonSpaceIndex) ?? nextNonSpaceIndex
                    nextNonSpaceIndex = formatter.index(of: .nonSpaceOrLinebreak,
                                                        before: nextNonSpaceIndex) ?? nextNonSpaceIndex
                    if let lineIndex = formatter.index(of: .linebreak, after: nextNonSpaceIndex),
                       let nextToken = formatter.next(.nonSpace, after: lineIndex),
                       [.startOfScope("#if"), .keyword("#else"), .keyword("#elseif")].contains(nextToken)
                    {
                        break
                    }
                    fallthrough
                case .startOfScope("#if"):
                    if let lineIndex = formatter.index(of: .linebreak, after: nextNonSpaceIndex),
                       let nextKeyword = formatter.next(.nonSpaceOrCommentOrLinebreak, after: lineIndex), [
                           .endOfScope("case"), .endOfScope("default"), .keyword("@unknown"),
                       ].contains(nextKeyword)
                    {
                        break
                    }
                    formatter.insertSpaceIfEnabled(indent, at: i + 1)
                case .endOfScope, .keyword("@unknown"):
                    if let scope = scopeStack.last {
                        switch scope {
                        case .startOfScope("/*"), .startOfScope("#if"),
                             .keyword("#else"), .keyword("#elseif"),
                             .startOfScope where scope.isStringDelimiter:
                            formatter.insertSpaceIfEnabled(indent, at: i + 1)
                        default:
                            break
                        }
                    }
                default:
                    var lastIndex = lastNonSpaceOrLinebreakIndex > -1 ? lastNonSpaceOrLinebreakIndex : i
                    while formatter.token(at: lastIndex) == .endOfScope("#endif"),
                          let index = formatter.index(of: .startOfScope, before: lastIndex, if: {
                              $0 == .startOfScope("#if")
                          })
                    {
                        lastIndex = formatter.index(
                            of: .nonSpaceOrCommentOrLinebreak,
                            before: index
                        ) ?? index
                    }
                    let lastToken = formatter.tokens[lastIndex]
                    if [.endOfScope("}"), .endOfScope(")")].contains(lastToken),
                       lastIndex == formatter.startOfLine(at: lastIndex, excludingIndent: true),
                       formatter.token(at: nextNonSpaceIndex) == .operator(".", .infix) ||
                       (lastToken == .endOfScope("}") && formatter.isLabel(at: nextNonSpaceIndex))
                    {
                        indent = formatter.currentIndentForLine(at: lastIndex)
                    }
                    if formatter.options.fragment, lastToken == .delimiter(",") {
                        break // Can't reliably indent
                    }
                    formatter.insertSpaceIfEnabled(indent, at: i + 1)
                }

                if linewrapped, shouldIndentNextLine(at: i) {
                    indentStack[indentStack.count - 1] += formatter.options.indent
                }
            default:
                break
            }
            // Track token for line wraps
            if !token.isSpaceOrComment {
                lastNonSpaceIndex = i
                if !token.isLinebreak {
                    lastNonSpaceOrLinebreakIndex = i
                }
            }
        }

        if formatter.options.indentStrings {
            formatter.forEach(.startOfScope("\"\"\"")) { stringStartIndex, _ in
                let baseIndent = formatter.currentIndentForLine(at: stringStartIndex)
                let expectedIndent = baseIndent + formatter.options.indent

                guard let stringEndIndex = formatter.endOfScope(at: stringStartIndex),
                      // Preserve the default indentation if the opening """ is on a line by itself
                      formatter.startOfLine(at: stringStartIndex, excludingIndent: true) != stringStartIndex
                else { return }

                for linebreakIndex in (stringStartIndex ..< stringEndIndex).reversed()
                    where formatter.tokens[linebreakIndex].isLinebreak
                {
                    // If this line is completely blank, do nothing
                    //  - This prevents conflicts with the trailingSpace rule
                    if formatter.nextToken(after: linebreakIndex)?.isLinebreak == true {
                        continue
                    }

                    let indentIndex = linebreakIndex + 1
                    if formatter.tokens[indentIndex].is(.space) {
                        formatter.replaceToken(at: indentIndex, with: .space(expectedIndent))
                    } else {
                        formatter.insert(.space(expectedIndent), at: indentIndex)
                    }
                }
            }
        }
    }
}