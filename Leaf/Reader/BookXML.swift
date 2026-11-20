// SPDX-License-Identifier: GPL-3.0-only

import Foundation

final class BookXML: NSObject, XMLParserDelegate {
    final class Node {
        enum Content {
            case text(String)
            case element(Node)
        }

        let name: String
        var attributes: [String: String]
        var content: [Content] = []

        init(name: String, attributes: [String: String]) {
            self.name = name.split(separator: ":").last.map(String.init) ?? name
            self.attributes = attributes
        }

        var children: [Node] {
            content.compactMap { if case .element(let child) = $0 { child } else { nil } }
        }

        var label: String { textContent.trimmingCharacters(in: .whitespacesAndNewlines) }

        private var textContent: String {
            content.map {
                switch $0 {
                case .text(let text): text
                case .element(let node): node.textContent
                }
            }.joined()
        }

        func child(_ name: String) -> Node? { children.first { $0.name == name } }

        func all(_ name: String) -> [Node] {
            var result: [Node] = []
            collect(name, into: &result)
            return result
        }

        private func collect(_ name: String, into result: inout [Node]) {
            for child in children {
                if child.name == name { result.append(child) }
                child.collect(name, into: &result)
            }
        }
    }

    private static let commonEntities = [
        "nbsp": 160, "ndash": 8211, "mdash": 8212, "hellip": 8230, "lsquo": 8216, "rsquo": 8217,
        "ldquo": 8220, "rdquo": 8221, "laquo": 171, "raquo": 187, "copy": 169, "reg": 174,
        "trade": 8482, "bull": 8226, "middot": 183, "thinsp": 8201, "shy": 173,
    ]

    private var root: Node?
    private var stack: [Node] = []
    private var nodes = 0

    static func parse(_ data: Data) throws -> Node {
        let encoding: String.Encoding = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
            ? .utf16 : .utf8
        guard var text = String(data: data, encoding: encoding), !text.contains("\0") else {
            throw EbookError.invalidMarkup
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        if text.hasPrefix("<?xml "), let declaration = text.range(of: "?>") {
            text.removeSubrange(..<declaration.upperBound)
        }
        if let start = text.range(of: "<!DOCTYPE", options: .caseInsensitive) {
            guard let end = text[start.upperBound...].firstIndex(of: ">"),
                  isKnownDoctype(String(text[start.lowerBound...end])) else { throw EbookError.invalidMarkup }
            text.removeSubrange(start.lowerBound...end)
            guard text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else {
                throw EbookError.invalidMarkup
            }
        }
        for (entity, scalar) in commonEntities {
            text = text.replacingOccurrences(of: "&\(entity);", with: "&#\(scalar);")
        }
        let delegate = BookXML()
        let parser = XMLParser(data: Data(text.utf8))
        parser.externalEntityResolvingPolicy = .never
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw EbookError.invalidMarkup }
        return root
    }

    private static func isKnownDoctype(_ declaration: String) -> Bool {
        // Strip the standard external identifiers without loading them.
        let value = declaration.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "'", with: "\"")
            .replacingOccurrences(of: "https://", with: "http://")
        switch value {
        case "<!DOCTYPE html>",
             #"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">"#,
             #"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">"#,
             #"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">"#,
             #"<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">"#:
            return true
        default:
            return false
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        nodes += 1
        guard nodes <= 100_000, stack.count < 64 else {
            parser.abortParsing()
            return
        }
        let node = Node(name: elementName, attributes: attributes)
        if let parent = stack.last { parent.content.append(.element(node)) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.content.append(.text(string))
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if let text = String(data: data, encoding: .utf8) { stack.last?.content.append(.text(text)) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        _ = stack.popLast()
    }
}
