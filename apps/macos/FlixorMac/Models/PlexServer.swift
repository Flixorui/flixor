//
//  PlexServer.swift
//  FlixorMac
//
//  Models for Plex server connections
//

import Foundation

struct PlexServer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let host: String?
    let port: Int?
    let protocolName: String?
    let preferredUri: String?
    let publicAddress: String?
    let localAddresses: [String]?
    let machineIdentifier: String?
    let isActive: Bool?
    let owned: Bool?
    let presence: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case preferredUri
        case publicAddress
        case localAddresses
        case machineIdentifier
        case isActive
        case owned
        case presence
        case protocolName = "protocol"
    }

    var baseURLDisplay: String {
        // If preferredUri is a full URL, use it directly
        if let uri = preferredUri, uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return uri
        }
        // If host looks like a full URL, use it directly
        if let hostValue = host, hostValue.hasPrefix("http://") || hostValue.hasPrefix("https://") {
            return hostValue
        }
        // Otherwise construct from parts
        let proto = (protocolName?.isEmpty == false ? protocolName! : "http")
        let hostValue = host ?? "—"
        let formattedHost = hostValue.contains(":") && !hostValue.contains("[") && !hostValue.contains("]")
            ? "[\(hostValue)]"
            : hostValue
        let resolvedPort = port ?? (proto == "https" ? 443 : 32400)
        return "\(proto)://\(formattedHost):\(resolvedPort)"
    }
}

struct PlexConnection: Codable, Identifiable, Hashable {
    let uri: String
    let protocolName: String?
    let local: Bool?
    let relay: Bool?
    let IPv6: Bool?
    let isCurrent: Bool?
    let isPreferred: Bool?

    var id: String { uri }

    enum CodingKeys: String, CodingKey {
        case uri
        case protocolName = "protocol"
        case local
        case relay
        case IPv6
        case isCurrent
        case isPreferred
    }
}

struct PlexConnectionsResponse: Codable {
    let serverId: String?
    let connections: [PlexConnection]
}

struct PlexAuthServer: Codable {
    let clientIdentifier: String
    let token: String
    let name: String?
}
