import XCTest

#if canImport(kshr_DEV)
@testable import kshr_DEV
#elseif canImport(kshr)
@testable import kshr
#endif

// MARK: - JSON Decoding

final class KshrConfigDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> KshrConfigFile {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(KshrConfigFile.self, from: data)
    }

    // MARK: Simple commands

    func testDecodeSimpleCommand() throws {
        let json = """
        {
          "commands": [{
            "name": "Run tests",
            "command": "npm test"
          }]
        }
        """
        let config = try decode(json)
        XCTAssertEqual(config.commands.count, 1)
        XCTAssertEqual(config.commands[0].name, "Run tests")
        XCTAssertEqual(config.commands[0].command, "npm test")
        XCTAssertNil(config.commands[0].workspace)
    }

    func testDecodeSimpleCommandWithAllFields() throws {
        let json = """
        {
          "commands": [{
            "name": "Deploy",
            "description": "Deploy to production",
            "keywords": ["ship", "release"],
            "command": "make deploy",
            "confirm": true
          }]
        }
        """
        let config = try decode(json)
        let cmd = config.commands[0]
        XCTAssertEqual(cmd.name, "Deploy")
        XCTAssertEqual(cmd.description, "Deploy to production")
        XCTAssertEqual(cmd.keywords, ["ship", "release"])
        XCTAssertEqual(cmd.command, "make deploy")
        XCTAssertEqual(cmd.confirm, true)
    }

    func testDecodeMultipleCommands() throws {
        let json = """
        {
          "commands": [
            { "name": "Build", "command": "make build" },
            { "name": "Test", "command": "make test" },
            { "name": "Lint", "command": "make lint" }
          ]
        }
        """
        let config = try decode(json)
        XCTAssertEqual(config.commands.count, 3)
        XCTAssertEqual(config.commands.map(\.name), ["Build", "Test", "Lint"])
    }

    func testDecodeEmptyCommandsArray() throws {
        let json = """
        { "commands": [] }
        """
        let config = try decode(json)
        XCTAssertTrue(config.commands.isEmpty)
    }

    // MARK: Workspace commands

    func testDecodeWorkspaceCommand() throws {
        let json = """
        {
          "commands": [{
            "name": "Dev env",
            "workspace": {
              "name": "Development",
              "cwd": "~/projects/app",
              "color": "#FF5733"
            }
          }]
        }
        """
        let config = try decode(json)
        let ws = config.commands[0].workspace
        XCTAssertNotNil(ws)
        XCTAssertEqual(ws?.name, "Development")
        XCTAssertEqual(ws?.cwd, "~/projects/app")
        XCTAssertEqual(ws?.color, "#FF5733")
    }

    func testDecodeRestartBehaviors() throws {
        for behavior in ["recreate", "ignore", "confirm"] {
            let json = """
            {
              "commands": [{
                "name": "test",
                "restart": "\(behavior)",
                "workspace": { "name": "ws" }
              }]
            }
            """
            let config = try decode(json)
            XCTAssertEqual(config.commands[0].restart?.rawValue, behavior)
        }
    }

    // MARK: Layout tree

    func testDecodePaneNode() throws {
        let json = """
        {
          "commands": [{
            "name": "layout",
            "workspace": {
              "layout": {
                "pane": {
                  "surfaces": [
                    { "type": "terminal", "name": "shell" }
                  ]
                }
              }
            }
          }]
        }
        """
        let config = try decode(json)
        let layout = config.commands[0].workspace!.layout!
        if case .pane(let pane) = layout {
            XCTAssertEqual(pane.surfaces.count, 1)
            XCTAssertEqual(pane.surfaces[0].type, .terminal)
            XCTAssertEqual(pane.surfaces[0].name, "shell")
        } else {
            XCTFail("Expected pane node")
        }
    }

    func testDecodeSplitNode() throws {
        let json = """
        {
          "commands": [{
            "name": "layout",
            "workspace": {
              "layout": {
                "direction": "horizontal",
                "split": 0.3,
                "children": [
                  { "pane": { "surfaces": [{ "type": "terminal" }] } },
                  { "pane": { "surfaces": [{ "type": "terminal" }] } }
                ]
              }
            }
          }]
        }
        """
        let config = try decode(json)
        let layout = config.commands[0].workspace!.layout!
        if case .split(let split) = layout {
            XCTAssertEqual(split.direction, .horizontal)
            XCTAssertEqual(split.split, 0.3)
            XCTAssertEqual(split.children.count, 2)
        } else {
            XCTFail("Expected split node")
        }
    }

    func testDecodeNestedSplits() throws {
        let json = """
        {
          "commands": [{
            "name": "nested",
            "workspace": {
              "layout": {
                "direction": "horizontal",
                "children": [
                  { "pane": { "surfaces": [{ "type": "terminal" }] } },
                  {
                    "direction": "vertical",
                    "children": [
                      { "pane": { "surfaces": [{ "type": "terminal" }] } },
                      { "pane": { "surfaces": [{ "type": "browser", "url": "http://localhost:3000" }] } }
                    ]
                  }
                ]
              }
            }
          }]
        }
        """
        let config = try decode(json)
        let layout = config.commands[0].workspace!.layout!
        if case .split(let outer) = layout {
            XCTAssertEqual(outer.direction, .horizontal)
            if case .split(let inner) = outer.children[1] {
                XCTAssertEqual(inner.direction, .vertical)
                if case .pane(let browserPane) = inner.children[1] {
                    XCTAssertEqual(browserPane.surfaces[0].type, .browser)
                    XCTAssertEqual(browserPane.surfaces[0].url, "http://localhost:3000")
                } else {
                    XCTFail("Expected pane node for inner second child")
                }
            } else {
                XCTFail("Expected split node for outer second child")
            }
        } else {
            XCTFail("Expected split node")
        }
    }

    // MARK: Surface definitions

    func testDecodeTerminalSurfaceAllFields() throws {
        let json = """
        {
          "commands": [{
            "name": "test",
            "workspace": {
              "layout": {
                "pane": {
                  "surfaces": [{
                    "type": "terminal",
                    "name": "server",
                    "command": "npm start",
                    "cwd": "./backend",
                    "env": { "NODE_ENV": "development", "PORT": "3000" },
                    "focus": true
                  }]
                }
              }
            }
          }]
        }
        """
        let config = try decode(json)
        let surface = config.commands[0].workspace!.layout!
        if case .pane(let pane) = surface {
            let s = pane.surfaces[0]
            XCTAssertEqual(s.type, .terminal)
            XCTAssertEqual(s.name, "server")
            XCTAssertEqual(s.command, "npm start")
            XCTAssertEqual(s.cwd, "./backend")
            XCTAssertEqual(s.env, ["NODE_ENV": "development", "PORT": "3000"])
            XCTAssertEqual(s.focus, true)
            XCTAssertNil(s.url)
        } else {
            XCTFail("Expected pane node")
        }
    }

    func testDecodeBrowserSurface() throws {
        let json = """
        {
          "commands": [{
            "name": "test",
            "workspace": {
              "layout": {
                "pane": {
                  "surfaces": [{
                    "type": "browser",
                    "name": "Preview",
                    "url": "http://localhost:8080"
                  }]
                }
              }
            }
          }]
        }
        """
        let config = try decode(json)
        if case .pane(let pane) = config.commands[0].workspace!.layout! {
            let s = pane.surfaces[0]
            XCTAssertEqual(s.type, .browser)
            XCTAssertEqual(s.url, "http://localhost:8080")
        } else {
            XCTFail("Expected pane node")
        }
    }

    func testDecodeMultipleSurfacesInPane() throws {
        let json = """
        {
          "commands": [{
            "name": "test",
            "workspace": {
              "layout": {
                "pane": {
                  "surfaces": [
                    { "type": "terminal", "name": "shell1" },
                    { "type": "terminal", "name": "shell2" },
                    { "type": "browser", "name": "web" }
                  ]
                }
              }
            }
          }]
        }
        """
        let config = try decode(json)
        if case .pane(let pane) = config.commands[0].workspace!.layout! {
            XCTAssertEqual(pane.surfaces.count, 3)
            XCTAssertEqual(pane.surfaces.map(\.name), ["shell1", "shell2", "web"])
        } else {
            XCTFail("Expected pane node")
        }
    }

    // MARK: Decoding errors

    func testDecodeInvalidLayoutNodeThrows() {
        let json = """
        {
          "commands": [{
            "name": "bad",
            "workspace": {
              "layout": { "invalid": true }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeMissingCommandsKeyThrows() {
        let json = """
        { "notCommands": [] }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeInvalidSurfaceTypeThrows() {
        let json = """
        {
          "commands": [{
            "name": "test",
            "workspace": {
              "layout": {
                "pane": {
                  "surfaces": [{ "type": "invalidType" }]
                }
              }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: Command validation

    func testDecodeCommandWithNeitherWorkspaceNorCommandThrows() {
        let json = """
        {
          "commands": [{
            "name": "empty"
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeCommandWithBothWorkspaceAndCommandThrows() {
        let json = """
        {
          "commands": [{
            "name": "hybrid",
            "command": "echo hi",
            "workspace": { "name": "ws" }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: Layout validation

    func testDecodeLayoutNodeWithBothPaneAndDirectionThrows() {
        let json = """
        {
          "commands": [{
            "name": "ambiguous",
            "workspace": {
              "layout": {
                "pane": { "surfaces": [{ "type": "terminal" }] },
                "direction": "horizontal",
                "children": [
                  { "pane": { "surfaces": [{ "type": "terminal" }] } },
                  { "pane": { "surfaces": [{ "type": "terminal" }] } }
                ]
              }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeSplitWithWrongChildrenCountThrows() {
        let json = """
        {
          "commands": [{
            "name": "bad-split",
            "workspace": {
              "layout": {
                "direction": "horizontal",
                "children": [
                  { "pane": { "surfaces": [{ "type": "terminal" }] } }
                ]
              }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeSplitWithThreeChildrenThrows() {
        let json = """
        {
          "commands": [{
            "name": "bad-split",
            "workspace": {
              "layout": {
                "direction": "vertical",
                "children": [
                  { "pane": { "surfaces": [{ "type": "terminal" }] } },
                  { "pane": { "surfaces": [{ "type": "terminal" }] } },
                  { "pane": { "surfaces": [{ "type": "terminal" }] } }
                ]
              }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodePaneWithEmptySurfacesThrows() {
        let json = """
        {
          "commands": [{
            "name": "empty-pane",
            "workspace": {
              "layout": {
                "pane": { "surfaces": [] }
              }
            }
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeBlankNameThrows() {
        let json = """
        {
          "commands": [{
            "name": "",
            "command": "echo hi"
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeWhitespaceOnlyNameThrows() {
        let json = """
        {
          "commands": [{
            "name": "   ",
            "command": "echo hi"
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeBlankCommandThrows() {
        let json = """
        {
          "commands": [{
            "name": "test",
            "command": ""
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodeWhitespaceOnlyCommandThrows() {
        let json = """
        {
          "commands": [{
            "name": "test",
            "command": "   "
          }]
        }
        """
        XCTAssertThrowsError(try decode(json))
    }
}

// MARK: - Command identity

final class KshrCommandIdentityTests: XCTestCase {

    func testCommandIdIsDeterministic() {
        let cmd = KshrCommandDefinition(name: "Run tests", command: "test")
        XCTAssertEqual(cmd.id, "kshr.config.command.Run%20tests")
    }

    func testCommandIdEncodesSpecialCharacters() {
        let cmd = KshrCommandDefinition(name: "build & deploy", command: "make")
        XCTAssertTrue(cmd.id.hasPrefix("kshr.config.command."))
        XCTAssertFalse(cmd.id.contains("&"))
        XCTAssertFalse(cmd.id.contains(" "))
    }

    func testCommandIdIsUniqueForDifferentNames() {
        let cmd1 = KshrCommandDefinition(name: "build", command: "make build")
        let cmd2 = KshrCommandDefinition(name: "test", command: "make test")
        XCTAssertNotEqual(cmd1.id, cmd2.id)
    }

    func testCommandIdDoesNotCollideWithBuiltinPrefix() {
        let cmd = KshrCommandDefinition(name: "palette.newWorkspace", command: "echo")
        XCTAssertTrue(cmd.id.hasPrefix("kshr.config.command."))
        XCTAssertNotEqual(cmd.id, "palette.newWorkspace")
    }
}

// MARK: - Split clamping

final class KshrSplitDefinitionTests: XCTestCase {

    func testClampedSplitPositionDefaultsToHalf() {
        let split = KshrSplitDefinition(direction: .horizontal, split: nil, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.5)
    }

    func testClampedSplitPositionPassesThroughValidValue() {
        let split = KshrSplitDefinition(direction: .vertical, split: 0.3, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.3, accuracy: 0.001)
    }

    func testClampedSplitPositionClampsLow() {
        let split = KshrSplitDefinition(direction: .horizontal, split: 0.01, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.1, accuracy: 0.001)
    }

    func testClampedSplitPositionClampsHigh() {
        let split = KshrSplitDefinition(direction: .horizontal, split: 0.99, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.9, accuracy: 0.001)
    }

    func testClampedSplitPositionClampsNegative() {
        let split = KshrSplitDefinition(direction: .horizontal, split: -1.0, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.1, accuracy: 0.001)
    }

    func testClampedSplitPositionClampsAboveOne() {
        let split = KshrSplitDefinition(direction: .horizontal, split: 2.0, children: [])
        XCTAssertEqual(split.clampedSplitPosition, 0.9, accuracy: 0.001)
    }

    func testSplitOrientationHorizontal() {
        let split = KshrSplitDefinition(direction: .horizontal, split: nil, children: [])
        XCTAssertEqual(split.splitOrientation, .horizontal)
    }

    func testSplitOrientationVertical() {
        let split = KshrSplitDefinition(direction: .vertical, split: nil, children: [])
        XCTAssertEqual(split.splitOrientation, .vertical)
    }
}

// MARK: - CWD resolution

@MainActor
final class KshrConfigCwdResolutionTests: XCTestCase {

    private let baseCwd = "/Users/test/project"

    func testNilCwdReturnsBase() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd(nil, relativeTo: baseCwd),
            baseCwd
        )
    }

    func testEmptyCwdReturnsBase() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("", relativeTo: baseCwd),
            baseCwd
        )
    }

    func testDotCwdReturnsBase() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd(".", relativeTo: baseCwd),
            baseCwd
        )
    }

    func testAbsolutePathReturnedAsIs() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("/tmp/other", relativeTo: baseCwd),
            "/tmp/other"
        )
    }

    func testRelativePathJoinedToBase() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("backend/src", relativeTo: baseCwd),
            "/Users/test/project/backend/src"
        )
    }

    func testTildeExpandsToHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("~", relativeTo: baseCwd),
            home
        )
    }

    func testTildeSlashExpandsToHomePlusPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("~/Documents/work", relativeTo: baseCwd),
            (home as NSString).appendingPathComponent("Documents/work")
        )
    }

    func testSingleSubdirectory() {
        XCTAssertEqual(
            KshrConfigStore.resolveCwd("src", relativeTo: baseCwd),
            "/Users/test/project/src"
        )
    }
}

// MARK: - Layout encoding round-trip

final class KshrLayoutEncodingTests: XCTestCase {

    func testPaneNodeRoundTrips() throws {
        let original = KshrLayoutNode.pane(KshrPaneDefinition(surfaces: [
            KshrSurfaceDefinition(type: .terminal, name: "shell")
        ]))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KshrLayoutNode.self, from: data)

        if case .pane(let pane) = decoded {
            XCTAssertEqual(pane.surfaces.count, 1)
            XCTAssertEqual(pane.surfaces[0].name, "shell")
        } else {
            XCTFail("Expected pane node after round-trip")
        }
    }

    func testSplitNodeRoundTrips() throws {
        let original = KshrLayoutNode.split(KshrSplitDefinition(
            direction: .vertical,
            split: 0.7,
            children: [
                .pane(KshrPaneDefinition(surfaces: [KshrSurfaceDefinition(type: .terminal)])),
                .pane(KshrPaneDefinition(surfaces: [KshrSurfaceDefinition(type: .browser, url: "http://localhost")]))
            ]
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KshrLayoutNode.self, from: data)

        if case .split(let split) = decoded {
            XCTAssertEqual(split.direction, .vertical)
            XCTAssertEqual(split.split, 0.7)
            XCTAssertEqual(split.children.count, 2)
        } else {
            XCTFail("Expected split node after round-trip")
        }
    }
}
