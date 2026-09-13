import XCTest
@testable import MagicPadCore

final class LANAddressTests: XCTestCase {
    func testRfc1918() {
        XCTAssertTrue(LANAddress.isPrivate("10.8.0.2")) // example-ip
        XCTAssertTrue(LANAddress.isPrivate("192.168.1.5")) // example-ip
        XCTAssertTrue(LANAddress.isPrivate("172.16.0.1")) // example-ip
        XCTAssertTrue(LANAddress.isPrivate("172.31.255.255")) // example-ip
    }

    func testRejectsLoopbackLinkLocalPublic() {
        XCTAssertFalse(LANAddress.isPrivate("127.0.0.1"))
        XCTAssertFalse(LANAddress.isPrivate("169.254.1.1"))
        XCTAssertFalse(LANAddress.isPrivate("8.8.8.8"))
        XCTAssertFalse(LANAddress.isPrivate("172.15.0.1"))
        XCTAssertFalse(LANAddress.isPrivate("172.32.0.1"))
        XCTAssertFalse(LANAddress.isPrivate("not-an-ip"))
        XCTAssertFalse(LANAddress.isPrivate("10.0.0")) // example-ip
        XCTAssertFalse(LANAddress.isPrivate("10.a.0.0.1")) // example-ip
        XCTAssertFalse(LANAddress.isPrivate("10.0.0.1.")) // example-ip
        XCTAssertFalse(LANAddress.isPrivate("10.999.0.0")) // example-ip
        XCTAssertFalse(LANAddress.isPrivate("192.168.-1.0")) // example-ip
    }
}
