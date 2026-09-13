import XCTest
@testable import MagicPadCore

final class Cycle21QRNeverEmbedsTokenTests: XCTestCase {
    func testPlainAutoURLIsSafe() {
        let url = "http://10.8.0.2:7878/?auto=1&host=10.8.0.2" // example-ip
        XCTAssertTrue(PairingToken.qrURLIsSafe(url, configured: nil))
        XCTAssertTrue(PairingToken.qrURLIsSafe(url, configured: "secret"))
    }

    func testPairQueryAndEnvNameAreRejected() {
        XCTAssertFalse(PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?pair=secret")) // example-ip
        XCTAssertFalse(PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?PAIR=x")) // example-ip
        XCTAssertFalse(
            PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?x=\(PairingToken.envName)") // example-ip
        )
    }

    func testConfiguredTokenSubstringIsRejected() {
        XCTAssertFalse(
            PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?t=secret", configured: "secret") // example-ip
        )
    }

    func testQueryItemNamedPairIsRejected() {
        XCTAssertFalse(PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?pair")) // example-ip
        XCTAssertFalse(PairingToken.qrURLIsSafe("http://10.8.0.2:7878/?auto=1&pair=")) // example-ip
    }
}
