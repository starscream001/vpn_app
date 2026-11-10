import Foundation
import NetworkExtension
import Security
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter = WireGuardAdapter(with: self) { _, _ in }
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let account = proto.providerConfiguration?["keychainAccount"] as? String,
              let group = Bundle.main.object(forInfoDictionaryKey: "FoxWayKeychainGroup") as? String else {
            completionHandler(NSError(domain: "FoxWay.AWG", code: 1)); return
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FoxWay.AWG", kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let raw = String(data: data, encoding: .utf8) else {
            completionHandler(NSError(domain: "FoxWay.AWG", code: 2)); return
        }
        do {
            let config = try TunnelConfiguration(fromWgQuickConfig: raw, called: "FoxWay")
            adapter.start(tunnelConfiguration: config) { error in
                completionHandler(error == nil ? nil : NSError(domain: "FoxWay.AWG", code: 3))
            }
        } catch { completionHandler(NSError(domain: "FoxWay.AWG", code: 4)) }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "stats" else { completionHandler?(nil); return }
        adapter.getRuntimeConfiguration { raw in
            var rx: UInt64 = 0, tx: UInt64 = 0
            for line in (raw ?? "").split(separator: "\n") {
                let pair = line.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let value = UInt64(pair[1]) else { continue }
                if pair[0] == "rx_bytes" { rx += value }
                if pair[0] == "tx_bytes" { tx += value }
            }
            completionHandler?(try? JSONSerialization.data(withJSONObject: ["rx": rx, "tx": tx]))
        }
    }
}
