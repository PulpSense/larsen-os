import Foundation

enum PhraseTableAlignment: Equatable {
    case leading
    case center
    case trailing
}

struct PhraseMarkdownTable: Equatable {
    let headers: [String]
    let rows: [[String]]
    let alignments: [PhraseTableAlignment]
}

enum PhraseTableSizing {
    static func columnWidth(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return max(0, availableWidth) / CGFloat(columnCount)
    }
}

struct DesktopPhraseMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(Int)
        case bullet
        case numbered(String)
        case quote
        case paragraph
        case table(PhraseMarkdownTable)
        case spacer
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [DesktopPhraseMarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [DesktopPhraseMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            if index + 1 < lines.count,
               let headers = tableCells(in: lines[index]),
               let alignments = tableAlignments(in: lines[index + 1]),
               headers.count == alignments.count {
                var rows: [[String]] = []
                var rowIndex = index + 2
                while rowIndex < lines.count,
                      let cells = tableCells(in: lines[rowIndex]) {
                    rows.append(normalized(cells, count: headers.count))
                    rowIndex += 1
                }
                blocks.append(DesktopPhraseMarkdownBlock(
                    id: index,
                    kind: .table(PhraseMarkdownTable(
                        headers: headers,
                        rows: rows,
                        alignments: alignments
                    )),
                    text: ""
                ))
                index = rowIndex
                continue
            }

            blocks.append(parseLine(lines[index], index: index))
            index += 1
        }

        return blocks
    }

    private static func parseLine(_ rawLine: String, index: Int) -> DesktopPhraseMarkdownBlock {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            return DesktopPhraseMarkdownBlock(id: index, kind: .spacer, text: "")
        }

        let headingMarks = line.prefix { $0 == "#" }.count
        if (1...3).contains(headingMarks),
           line.dropFirst(headingMarks).hasPrefix(" ") {
            return DesktopPhraseMarkdownBlock(
                id: index,
                kind: .heading(headingMarks),
                text: String(line.dropFirst(headingMarks + 1))
            )
        }

        if line.hasPrefix("- ") || line.hasPrefix("+ ") || line.hasPrefix("* ") {
            return DesktopPhraseMarkdownBlock(
                id: index,
                kind: .bullet,
                text: String(line.dropFirst(2))
            )
        }

        if let dot = line.firstIndex(of: ".") {
            let digits = line[..<dot]
            let remainder = line[line.index(after: dot)...]
            if !digits.isEmpty,
               digits.allSatisfy(\.isNumber),
               remainder.hasPrefix(" ") {
                return DesktopPhraseMarkdownBlock(
                    id: index,
                    kind: .numbered("\(digits)."),
                    text: String(remainder.dropFirst())
                )
            }
        }

        if line.hasPrefix("> ") {
            return DesktopPhraseMarkdownBlock(
                id: index,
                kind: .quote,
                text: String(line.dropFirst(2))
            )
        }

        return DesktopPhraseMarkdownBlock(id: index, kind: .paragraph, text: line)
    }

    private static func tableCells(in rawLine: String) -> [String]? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.contains("|") else { return nil }
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }

        var cells = [""]
        var escaping = false
        for character in line {
            if escaping {
                if character != "|" { cells[cells.count - 1].append("\\") }
                cells[cells.count - 1].append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "|" {
                cells.append("")
            } else {
                cells[cells.count - 1].append(character)
            }
        }
        if escaping { cells[cells.count - 1].append("\\") }
        guard cells.count >= 2 else { return nil }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableAlignments(in rawLine: String) -> [PhraseTableAlignment]? {
        guard let cells = tableCells(in: rawLine) else { return nil }
        var alignments: [PhraseTableAlignment] = []

        for cell in cells {
            let marker = cell.filter { !$0.isWhitespace }
            let leadingColon = marker.hasPrefix(":")
            let trailingColon = marker.hasSuffix(":")
            let dashes = marker.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard dashes.count >= 3, dashes.allSatisfy({ $0 == "-" }) else { return nil }

            switch (leadingColon, trailingColon) {
            case (true, true): alignments.append(.center)
            case (false, true): alignments.append(.trailing)
            default: alignments.append(.leading)
            }
        }

        return alignments
    }

    private static func normalized(_ cells: [String], count: Int) -> [String] {
        Array((cells + Array(repeating: "", count: count)).prefix(count))
    }
}
