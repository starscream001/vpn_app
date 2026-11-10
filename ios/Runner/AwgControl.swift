import Flutter
import Foundation
import NetworkExtension
import Security

final class AwgControl {
    private let channel: FlutterMethodChannel
    private let bundle = "app.foxway.foxway.AWGPacketTunnel"
    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "app.foxway/apple-awg", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard error == nil else { result(FlutterError(code: "VPN", message: "Cannot load VPN profiles", details: nil)); return }
            let manager = managers?.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.bundle } ?? NETunnelProviderManager()
            switch call.method {
            case "stop":
                guard manager.protocolConfiguration != nil else { result(nil); return }
                manager.isOnDemandEnabled = false
                manager.saveToPreferences { error in
                    guard error == nil else { result(FlutterError(code: "VPN_STOP", message: "Cannot disable on-demand protection", details: nil)); return }
                    manager.connection.stopVPNTunnel(); result(nil)
                }
            case "stats":
                guard manager.connection.status == .connected, let session = manager.connection as? NETunnelProviderSession else {
                    result(["up": false, "rx": 0, "tx": 0]); return
                }
                do {
                    try session.sendProviderMessage(Data("stats".utf8)) { response in
                        let stats = response.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                        result(["up": true, "rx": stats["rx"] ?? 0, "tx": stats["tx"] ?? 0])
                    }
                } catch { result(["up": false, "rx": 0, "tx": 0]) }
            case "start":
                guard let args = call.arguments as? [String: Any], let config = args["config"] as? String,
                      config.utf8.count <= 1048576,
                      let group = Bundle.main.object(forInfoDictionaryKey: "FoxWayKeychainGroup") as? String else {
                    result(FlutterError(code: "CONFIG", message: "Invalid AWG input", details: nil)); return
                }
                manager.connection.stopVPNTunnel()
                let account = "foxway.awg.current"
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "FoxWay.AWG", kSecAttrAccount as String: account,
                    kSecAttrAccessGroup as String: group]
                let attributes: [String: Any] = [kSecValueData as String: Data(config.utf8),
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
                guard status == errSecSuccess else {
                    result(FlutterError(code: "KEYCHAIN", message: "Check shared Keychain signing entitlements", details: nil)); return
                }
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = self.bundle
                proto.serverAddress = "FoxWay AmneziaWG"
                let protected = args["killSwitch"] as? Bool ?? false
                proto.includeAllNetworks = protected
                proto.excludeLocalNetworks = !protected
                if #available(iOS 16.4, macOS 13.3, *) { proto.excludeAPNs = !protected }
                if protected {
                    let rule = NEOnDemandRuleConnect(); rule.interfaceTypeMatch = .any
                    manager.onDemandRules = [rule]
                }
                manager.isOnDemandEnabled = protected
                proto.providerConfiguration = ["keychainAccount": account]
                manager.protocolConfiguration = proto
                manager.localizedDescription = "FoxWay AmneziaWG"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    guard error == nil else { result(FlutterError(code: "VPN_SAVE", message: "VPN permission or signing failed", details: nil)); return }
                    manager.loadFromPreferences { error in
                        guard error == nil else { result(FlutterError(code: "VPN_LOAD", message: "Cannot load VPN profile", details: nil)); return }
                        do { try manager.connection.startVPNTunnel(); result(nil) }
                        catch { result(FlutterError(code: "VPN_START", message: "AWG extension could not start", details: nil)) }
                    }
                }
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
}
