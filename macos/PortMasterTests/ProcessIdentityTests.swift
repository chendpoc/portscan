import XCTest
@testable import PortMaster

final class ProcessIdentityTests: XCTestCase {
    func testCurrentProcessVisible() {
        let pid = pid_t(getpid())
        let start = ProcessIdentity.processStart(pid: pid)
        XCTAssertNotNil(start)
    }
}
