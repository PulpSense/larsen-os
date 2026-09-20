import Foundation

@main
enum PhraseMarkdownTests {
    static func main() {
        let markdown = """
        ## Priorities

        | Goal | Status | Score |
        | :--- | :----: | ----: |
        | **Launch** | Active | 10 |
        | Retention | Review | 8 |
        """
        let blocks = DesktopPhraseMarkdownBlock.parse(markdown)

        precondition(blocks.count == 3, "A Markdown table must be parsed as one block")
        guard case let .table(table) = blocks[2].kind else {
            preconditionFailure("A header and delimiter row must produce a table")
        }
        precondition(table.headers == ["Goal", "Status", "Score"])
        precondition(table.rows == [["**Launch**", "Active", "10"], ["Retention", "Review", "8"]])
        precondition(table.alignments == [.leading, .center, .trailing])

        let escaped = DesktopPhraseMarkdownBlock.parse("""
        | Item | Meaning |
        | --- | --- |
        | A \\| B | Combined |
        """)
        guard case let .table(escapedTable) = escaped[0].kind else {
            preconditionFailure("Escaped pipes must remain inside table cells")
        }
        precondition(escapedTable.rows[0][0] == "A | B")

        let ordinaryText = DesktopPhraseMarkdownBlock.parse("A | B")
        precondition(
            ordinaryText.count == 1 && ordinaryText[0].kind == .paragraph,
            "A pipe without a delimiter row must remain a paragraph"
        )

        precondition(
            PhraseTableSizing.columnWidth(availableWidth: 576, columnCount: 2) == 288,
            "Table columns must expand to fill the phrase container"
        )
        precondition(
            PhraseTableSizing.columnWidth(availableWidth: 900, columnCount: 3) == 300,
            "Table columns must respond when the phrase container is resized"
        )

        print("PASS: phrase Markdown tables")
    }
}
