import Foundation

/// Finds the App Group container the app and the widget extension share.
///
/// SideStore re-signs the app with a free Apple ID and renames App Group IDs (it adds a suffix), so the
/// ID in `project.yml` may not be the one the installed app is entitled to. SideStore (like AltStore)
/// lists the renamed IDs in the `ALTAppGroups` Info.plist key, so those are tried first. If no group
/// container can be written, the app and widgets run without shared data: widgets show an
/// "Open simplyHermes" state and every button goes through an App Intent, which runs in the app.
public enum SharedContainer {
    /// The App Group declared in `project.yml`.
    public static let declaredGroupID = "group.com.simplyjaytea.simplyhermes"
    /// Info.plist key where SideStore and AltStore list the App Group IDs they signed the app with.
    public static let sideStoreInfoKey = "ALTAppGroups"

    public enum Resolution: Equatable, Sendable {
        case appGroup(id: String, directory: URL)
        case unavailable(tried: [String])

        public var directory: URL? {
            if case .appGroup(_, let directory) = self { return directory }
            return nil
        }
    }

    /// Group IDs to try, best first: SideStore's renamed copy of ours, any other SideStore group, then ours.
    public static func candidateGroupIDs(infoDictionary: [String: Any]?) -> [String] {
        let listed = (infoDictionary?[sideStoreInfoKey] as? [String]) ?? []
        let ours = listed.filter { $0.hasPrefix(declaredGroupID) }
        let others = listed.filter { !$0.hasPrefix(declaredGroupID) }
        var seen = Set<String>()
        return (ours + others + [declaredGroupID]).filter { seen.insert($0).inserted }
    }

    /// Picks the first candidate whose container exists and can be written.
    ///
    /// - Parameters:
    ///   - containerURL: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` on device.
    ///   - isWritable: checks a directory by writing a small probe file.
    public static func resolve(
        infoDictionary: [String: Any]?,
        containerURL: (String) -> URL?,
        isWritable: (URL) -> Bool = SharedContainer.canWrite(to:)
    ) -> Resolution {
        let candidates = candidateGroupIDs(infoDictionary: infoDictionary)
        for id in candidates {
            guard let url = containerURL(id) else { continue }
            let directory = url.appendingPathComponent("Integration", isDirectory: true)
            if isWritable(directory) {
                return .appGroup(id: id, directory: directory)
            }
        }
        return .unavailable(tried: candidates)
    }

    /// Creates `directory` if needed and writes, then removes, a probe file.
    public static func canWrite(to directory: URL) -> Bool {
        let probe = directory.appendingPathComponent(".probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
}
