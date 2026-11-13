import Foundation
import Testing

@testable import HermesKit

/// Row 132: the bundled acknowledgements cover every package a build contains, each with its license text.
struct AcknowledgementsTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func bundled() throws -> Acknowledgements { try Acknowledgements.bundled() }

    private static func identity(_ url: String) -> String {
        let last = url.split(separator: "/").last.map(String.init) ?? url
        return (last.hasSuffix(".git") ? String(last.dropLast(4)) : last).lowercased()
    }

    @Test func everyResolvedPackageIsListedAtItsExactVersion() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Package.resolved"))
        let pins = try #require(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["pins"] as? [[String: Any]])
        let list = try bundled()
        #expect(!pins.isEmpty)
        for pin in pins {
            let id = try #require(pin["identity"] as? String)
            let version = (pin["state"] as? [String: Any])?["version"] as? String
            let entry = list.packages[id]
            #expect(entry != nil, "\(id) is in Package.resolved but not in the acknowledgements")
            #expect(entry?.version == version, "\(id): regenerate with tools/acknowledgements/generate.py")
        }
    }

    @Test func everyAppPackageInProjectYMLIsListedOrBuildOnly() throws {
        let yml = try String(contentsOf: Self.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let urls = yml.split(separator: "\n").compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            return text.hasPrefix("url: ") ? String(text.dropFirst(5)) : nil
        }
        let list = try bundled()
        #expect(urls.count >= 4)
        for url in urls {
            let id = Self.identity(url)
            #expect(list.packages[id] != nil || list.buildOnly[id] != nil, "\(url) is not acknowledged")
        }
    }

    @Test func everyNoticesRowIsListedAndTheOtherWayAround() throws {
        let notices = try String(
            contentsOf: Self.root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        let rows = notices.split(separator: "\n").filter { $0.hasPrefix("| [") }
        let listed = Set(
            rows.compactMap { row -> String? in
                guard let start = row.firstIndex(of: "("), let end = row.firstIndex(of: ")") else { return nil }
                return Self.identity(String(row[row.index(after: start)..<end]))
            })
        let list = try bundled()
        let shipped = Set(list.packages.keys)
        #expect(shipped.isSubset(of: listed), "missing from the notices: \(shipped.subtracting(listed).sorted())")
        let extra = listed.subtracting(shipped).subtracting(list.buildOnly.keys)
        #expect(extra.isEmpty, "in the notices but not shipped: \(extra.sorted())")
    }

    @Test func everyEntryCarriesItsLicenseText() throws {
        let list = try bundled()
        #expect(
            list.packages.count >= 15,
            "the shipped set is about twenty packages; see theListIsExactlyTheResolvedAppGraph")
        for entry in list.sortedPackages {
            #expect(entry.license != "NOASSERTION", "\(entry.name) has no license the generator could read")
            #expect(entry.licenseText.count > 500, "\(entry.name): license text missing")
            if entry.license == "Apache-2.0" {
                #expect(entry.licenseText.contains("Apache License"), "\(entry.name)")
            }
        }
        #expect(list.packages["swift-nio"]?.notice?.isEmpty == false, "Apache NOTICE files are carried")
    }

    @Test func theAppsOwnLicenseIsTheRepositorysMIT() throws {
        let license = try String(contentsOf: Self.root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let list = try bundled()
        #expect(list.app.license == "MIT")
        #expect(list.app.licenseText == license.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(list.app.licenseText.contains("Copyright (c) 2026 simplyjaytea"))
    }

    @Test func buildOnlyToolsSayWhy() throws {
        let list = try bundled()
        #expect(list.buildOnly["swift-syntax"] != nil)
        #expect(list.buildOnly.values.allSatisfy { !$0.isEmpty })
        #expect(list.packages["swift-syntax"] == nil)
    }

    /// The packages a built app contains, exactly: `tools/acknowledgements/app-graph.resolved` is SwiftPM's resolution of
    /// the app's own package set (this package plus project.yml's MLX and swift-transformers), made with a toolchain
    /// that can read mlx-swift's manifest. The list names exactly those, at those versions: none missing, none extra.
    @Test func theListIsExactlyTheResolvedAppGraph() throws {
        let data = try Data(
            contentsOf: Self.root.appendingPathComponent("tools/acknowledgements/app-graph.resolved"))
        let pins = try #require(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["pins"] as? [[String: Any]])
        let list = try bundled()
        var resolved: [String: String] = [:]
        for pin in pins {
            let id = try #require(pin["identity"] as? String)
            guard list.buildOnly[id] == nil else { continue }
            resolved[id] = ((pin["state"] as? [String: Any])?["version"] as? String) ?? ""
        }
        #expect(resolved.count > 15)
        let listed = Set(list.packages.keys)
        #expect(listed.subtracting(resolved.keys).sorted() == [], "listed but not in a built app")
        #expect(Set(resolved.keys).subtracting(listed).sorted() == [], "in a built app but not listed")
        for (id, version) in resolved {
            #expect(list.packages[id]?.version == version, "\(id) should be \(version)")
        }
        #expect(list.packages.values.allSatisfy { $0.version != nil }, "every version is exact")
    }
}
