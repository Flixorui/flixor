//
//  TraktService+PublicLists.swift
//  FlixorKit
//
//  Public Trakt lists: resolve a pasted list URL, search lists by name and page
//  through a list's movies and shows. Client id only, so no Trakt login needed.
//

import Foundation

// MARK: - Reference

/// A Trakt list named by a pasted URL.
public enum TraktListReference: Hashable, Sendable {
    case id(Int)
    case slug(String)
    case userList(user: String, list: String)

    /// Parses `trakt.tv/users/<user>/lists/<slug>`, `trakt.tv/lists/<id or slug>`
    /// and `trakt.tv/lists/official/<slug>` (scheme and `app.` host optional).
    /// Returns nil for anything else, so callers can treat the text as a search.
    public init?(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().contains("trakt.tv/"),
              let url = URL(string: trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)") else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 4, parts[0] == "users", parts[2] == "lists" {
            self = .userList(user: parts[1], list: parts[3])
        } else if parts.count >= 3, parts[0] == "lists", parts[1] == "official" {
            self = .slug(parts[2])
        } else if parts.count >= 2, parts[0] == "lists" {
            if let id = Int(parts[1]) {
                self = .id(id)
            } else {
                self = .slug(parts[1])
            }
        } else {
            return nil
        }
    }

    var path: String {
        func encoded(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
        switch self {
        case .id(let id): return "/lists/\(id)"
        case .slug(let slug): return "/lists/\(encoded(slug))"
        case .userList(let user, let list): return "/users/\(encoded(user))/lists/\(encoded(list))"
        }
    }
}

// MARK: - Models

public struct TraktPublicList: Decodable, Identifiable, Hashable {
    public struct Ids: Decodable, Hashable {
        public let trakt: Int
        public let slug: String?
    }

    public struct Owner: Decodable, Hashable {
        public let username: String?
        public let name: String?
    }

    public let name: String
    public let description: String?
    public let itemCount: Int?
    public let likes: Int?
    public let ids: Ids
    public let user: Owner?

    public var id: Int { ids.trakt }

    private enum CodingKeys: String, CodingKey {
        case name, description, likes, ids, user
        case itemCount = "item_count"
    }
}

/// A movie or show on a public list.
public struct TraktPublicListMedia: Decodable {
    public let title: String?
    public let year: Int?
    public let overview: String?
    public let rating: Double?
    public let released: String?
    public let firstAired: String?
    public let ids: TraktIds?
    /// Full https URLs, when Trakt has artwork.
    public let posterURL: String?
    public let fanartURL: String?

    private struct Images: Decodable {
        let poster: [String]?
        let fanart: [String]?
    }

    private enum CodingKeys: String, CodingKey {
        case title, year, overview, rating, released, ids, images
        case firstAired = "first_aired"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        year = try? container.decodeIfPresent(Int.self, forKey: .year)
        overview = try? container.decodeIfPresent(String.self, forKey: .overview)
        rating = try? container.decodeIfPresent(Double.self, forKey: .rating)
        released = try? container.decodeIfPresent(String.self, forKey: .released)
        firstAired = try? container.decodeIfPresent(String.self, forKey: .firstAired)
        ids = try? container.decodeIfPresent(TraktIds.self, forKey: .ids)
        // Artwork is optional decoration: never fail an item over it.
        let images = (try? container.decodeIfPresent(Images.self, forKey: .images)) ?? nil
        posterURL = Self.absolute(images?.poster?.first)
        fanartURL = Self.absolute(images?.fanart?.first)
    }

    /// Trakt image paths come without a scheme ("media.trakt.tv/images/...").
    private static func absolute(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return path.lowercased().hasPrefix("http") ? path : "https://\(path)"
    }
}

public struct TraktPublicListEntry: Decodable {
    public let movie: TraktPublicListMedia?
    public let show: TraktPublicListMedia?
}

private struct TraktListSearchHit: Decodable {
    let list: TraktPublicList?
}

// MARK: - Endpoints

extension TraktService {
    /// Details of a public list. A private or deleted list is a 404.
    public func getPublicList(_ reference: TraktListReference) async throws -> TraktPublicList {
        let (data, _) = try await send(method: "GET", path: reference.path, params: ["extended": "full"])
        return try JSONDecoder().decode(TraktPublicList.self, from: data)
    }

    /// Searches public lists by name.
    public func searchPublicLists(query: String, page: Int = 1, limit: Int = 20) async throws -> [TraktPublicList] {
        let (data, _) = try await send(
            method: "GET",
            path: "/search/list",
            params: ["query": query, "page": String(page), "limit": String(limit), "extended": "full"]
        )
        return try JSONDecoder().decode([TraktListSearchHit].self, from: data).compactMap(\.list)
    }

    /// One page of a public list's movies and shows, in list order.
    public func getPublicListItems(listId: Int, page: Int = 1, limit: Int = 50) async throws -> TraktPage<TraktPublicListEntry> {
        let (data, response) = try await send(
            method: "GET",
            path: "/lists/\(listId)/items/movie,show",
            params: ["page": String(page), "limit": String(limit), "extended": "full,images"]
        )
        let items = try JSONDecoder().decode([TraktPublicListEntry].self, from: data)
        func header(_ name: String) -> Int? {
            (response.value(forHTTPHeaderField: name)).flatMap(Int.init)
        }
        return TraktPage(
            items: items,
            page: page,
            limit: limit,
            pageCount: header("X-Pagination-Page-Count") ?? page,
            itemCount: header("X-Pagination-Item-Count") ?? items.count
        )
    }
}
