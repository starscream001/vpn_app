import Foundation
import Security
import os

/// File locations shared by the app and the Packet Tunnel extension.
///
/// | Purpose | Location |
/// | --- | --- |
/// | libbox base path (`command.sock`) | app group container |
/// | libbox working path | `<container>/sing-box` |
/// | libbox temp path | `<container>/Library/Caches/sing-box` |
/// | last config | shared Keychain (FoxWay modification) |
/// | last start/stop error | `<working>/last_error` |
public struct SingBoxPaths {
    private static let logger = Logger(subsystem: "sing_box", category: "Paths")

    /// The app group these paths belong to.
    public let appGroup: String
    /// The app group container, or a private fallback directory when the
    /// container is not available (see [isAppGroupContainer]).
    public let baseDirectory: URL
    /// `false` when the process is not entitled to [appGroup]. The app and
    /// the extension then cannot exchange the configuration, so the tunnel
    /// cannot work.
    public let isAppGroupContainer: Bool

    public init(appGroup: String, baseDirectory: URL, isAppGroupContainer: Bool) {
        self.appGroup = appGroup
        self.baseDirectory = baseDirectory
        self.isAppGroupContainer = isAppGroupContainer
    }

    /// Resolves the container of `appGroup`. When the process is not entitled
    /// to the group, a clear error is logged and a private directory is used
    /// so that configuration checks still work.
    public static func resolve(appGroup: String) -> SingBoxPaths {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return SingBoxPaths(appGroup: appGroup, baseDirectory: container, isAppGroupContainer: true)
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sing_box", isDirectory: true)
        logger.error("""
        sing_box: the app group container for "\(appGroup, privacy: .public)" is not available. \
        Add the App Groups capability with this group to BOTH the app and the Packet Tunnel \
        extension (same team), or pass the right group in SingBoxIosOptions.appGroup. \
        The VPN cannot work until this is fixed.
        """)
        NSLog("[sing_box] ERROR: app group container for \"%@\" is not available (missing App Groups entitlement or team mismatch). Falling back to %@; the tunnel extension will not see the configuration.", appGroup, fallback.path)
        return SingBoxPaths(appGroup: appGroup, baseDirectory: fallback, isAppGroupContainer: false)
    }

    public var workingDirectory: URL {
        baseDirectory.appendingPathComponent("sing-box", isDirectory: true)
    }

    public var tempDirectory: URL {
        baseDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("sing-box", isDirectory: true)
    }

    public var configFile: URL {
        workingDirectory.appendingPathComponent("config.json", isDirectory: false)
    }

    public var lastErrorFile: URL {
        workingDirectory.appendingPathComponent("last_error", isDirectory: false)
    }

    public var commandSocket: URL {
        baseDirectory.appendingPathComponent("command.sock", isDirectory: false)
    }

    /// Shared `UserDefaults` of the app group (falls back to `.standard`).
    public var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public func createDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: Configuration

    // FoxWay: share credentials through Keychain, never a plaintext group file.
    private var configQuery: [String: Any]? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FoxWayKeychainGroup") as? String else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "FoxWay.VLESS",
                kSecAttrAccount as String: appGroup,
                kSecAttrAccessGroup as String: group]
    }

    public func readConfig() -> String? {
        guard var query = configQuery else { return nil }
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeConfig(_ config: String) throws {
        guard let query = configQuery else {
            throw NSError(domain: "FoxWay.Keychain", code: 1)
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(config.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "FoxWay.Keychain", code: Int(status))
        }
        // Remove any config left by an older upstream plugin implementation.
        try? FileManager.default.removeItem(at: configFile)
        writeLastError(nil)
    }

    // MARK: Last error

    public func readLastError() -> String? {
        guard let data = try? Data(contentsOf: lastErrorFile),
              let message = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return nil
        }
        return message
    }

    public func writeLastError(_ message: String?) {
        guard let message, !message.isEmpty else {
            try? FileManager.default.removeItem(at: lastErrorFile)
            return
        }
        try? createDirectories()
        // Native parser errors may contain credentials; persist only a generic marker.
        try? Data("VPN native error".utf8).write(to: lastErrorFile, options: [.atomic])
    }
}
