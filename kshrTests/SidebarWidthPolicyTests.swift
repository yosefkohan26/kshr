import XCTest

#if canImport(kshr_DEV)
@testable import kshr_DEV
#elseif canImport(kshr)
@testable import kshr
#endif

final class SidebarWidthPolicyTests: XCTestCase {
    func testContentViewClampAllowsNarrowSidebarBelowLegacyMinimum() {
        XCTAssertEqual(
            ContentView.clampedSidebarWidth(184, maximumWidth: 600),
            184,
            accuracy: 0.001
        )
    }
}
