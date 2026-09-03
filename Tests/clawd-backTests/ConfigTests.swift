import XCTest

@testable import clawd_back

final class AppConfigTests: XCTestCase {
  // The shape a user actually writes: one setting, not a restatement of every
  // default. A required field here fails the whole decode, and every setting
  // reverts silently.
  func testDecodesAConfigThatSetsOnlyOneField() throws {
    let config = try JSONDecoder().decode(
      AppConfig.self, from: Data(#"{"sound":"Blow"}"#.utf8))
    XCTAssertEqual(config.sound, "Blow")
    XCTAssertNil(config.application)
  }

  func testDecodesAnEmptyConfig() throws {
    let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
    XCTAssertNil(config.application)
    XCTAssertNil(config.sound)
    XCTAssertNil(config.bundleIdentifier)
    XCTAssertNil(config.forceWindowServerRaiseEnabled)
  }

  func testDecodesAFullConfig() throws {
    let config = try JSONDecoder().decode(
      AppConfig.self,
      from: Data(
        #"{"application":"generic","bundleIdentifier":"md.obsidian","sound":"Pop","forceWindowServerRaiseEnabled":true}"#
          .utf8))
    XCTAssertEqual(config.application, "generic")
    XCTAssertEqual(config.bundleIdentifier, "md.obsidian")
    XCTAssertEqual(config.forceWindowServerRaiseEnabled, true)
  }
}
