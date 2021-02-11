//
//  SpellVisitor.swift
//  typokana
//
//  Created by yuka ezura on 2019/04/29.
//

import Foundation
import Cocoa
import SwiftSyntax
import SwiftSyntaxExtensions

class SpellVisitor: SyntaxVisitor {
    let filePath: String
    let spellChecker: NSSpellChecker
    let sourceLocationConverter: SourceLocationConverter
    
    init(filePath: String, spellChecker: NSSpellChecker, sourceLocationConverter: SourceLocationConverter) {
        self.filePath = filePath
        self.spellChecker = spellChecker
        self.sourceLocationConverter = sourceLocationConverter
    }
    
    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        for comment in token.leadingTrivia.compactMap({ $0.comment }) {
            if ignoringSpellCheck(comment) {
                return .skipChildren
            }
            let commentWithStrippedURLs = comment.stringByRemovingURLs()
            let misspellRange = spellChecker.checkSpelling(of: commentWithStrippedURLs, startingAt: 0)
            if misspellRange.location < commentWithStrippedURLs.count {
                printMisspelled(forWordRange: misspellRange,
                                in: commentWithStrippedURLs,
                                position: sourceLocationConverter.location(for: token.positionAfterSkippingLeadingTrivia))
            }
        }
        
        switch token.tokenKind {
        case .stringLiteral(let text),
             .unknown(let text),
             .identifier(let text),
             .dollarIdentifier(let text),
             .stringSegment(let text):
            let formedText = text.stringByRemovingURLs()
                .stringBySplittingWhitespaces()
                .reduce([]) { (r, c) -> [String] in
                    var _r = r
                    if c.isUppercase {
                        _r.append(String(c))
                    } else if c == "_" || c == "." || c == "," || c.isNumber {
                        _r.append("")
                    } else {
                        var lastText = (_r.popLast() ?? "")
                        lastText.append(c)
                        _r.append(lastText)
                    }
                    return _r
                }.joined(separator: " ")
            let misspelledRange = spellChecker.checkSpelling(of: formedText, startingAt: 0)
            if misspelledRange.location < formedText.count {
                let position = sourceLocationConverter.location(for: token.position)
                printMisspelled(forWordRange: misspelledRange,
                                in: formedText,
                                position: position)
                // TODO: Resume check spelling from continuation of text
            }
        default:
            break
        }
        
        return .visitChildren
    }
    
    private func printMisspelled(forWordRange misspelledRange: NSRange, in string: String, position: SourceLocation) {
        let suggestedWord = spellChecker.correction(forWordRange: misspelledRange,
                                                             in: string,
                                                             language: spellChecker.language(),
                                                             inSpellDocumentWithTag: 0)
        var message: String {
            let targetWord = (string as NSString).substring(with: misspelledRange)
            if let suggestedWord = suggestedWord {
                return #""\#(targetWord)": did you mean "\#(suggestedWord)"? (CheckSpelling)"#
            } else {
                return #""\#(targetWord)" (CheckSpelling)"#
            }
        }
        
        guard let line = position.line, let column = position.column else {
            assertionFailure("Can't get position: \(position)")
            Diagnostics().emit(filePath: filePath,
                               line: 0,
                               column: 0,
                               message: message)
            return
        }
        
        Diagnostics().emit(filePath: filePath,
                           line: line,
                           column: column,
                           message: message)
    }

    private func ignoringSpellCheck(_ comment: String) -> Bool {

        return comment.trimmingCharacters(in: .whitespaces).contains("spellcheck:disable:this")
    }
}

private extension String {

    func stringByRemovingURLs() -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return self
        }
        return detector.stringByReplacingMatches(in: self,
                                                 options: [],
                                                 range: NSRange(location: 0, length: self.utf16.count),
                                                 withTemplate: "")
    }

    func stringBySplittingWhitespaces() -> String {

        return self.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
    }
}
