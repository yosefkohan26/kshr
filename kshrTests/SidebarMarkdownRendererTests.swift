import XCTest

#if canImport(kshr_DEV)
@testable import kshr_DEV
#elseif canImport(kshr)
@testable import kshr
#endif

final class SidebarMarkdownRendererTests: XCTestCase {
    func testRenderWorkspaceDescriptionPreservesLineBreaks() throws {
        let rendered = try XCTUnwrap(
            SidebarMarkdownRenderer.renderWorkspaceDescription("First line\nSecond line")
        )

        XCTAssertEqual(String(rendered.characters), "First line\nSecond line")
    }

    func testRenderWorkspaceDescriptionPreservesInlineMarkdownAttributes() throws {
        let rendered = try XCTUnwrap(
            SidebarMarkdownRenderer.renderWorkspaceDescription("**Bold**\n[Link](https://example.com)")
        )

        XCTAssertEqual(String(rendered.characters), "Bold\nLink")
        XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent != nil })
        XCTAssertTrue(
            rendered.runs.contains { $0.link == URL(string: "https://example.com") }
        )
    }
}
