//
//  TMDBService+CollectionSearch.swift
//  FlixorKit
//
//  Name search for production companies and movie collections, used when
//  building a custom collection. TMDB has no network search.
//

import Foundation

public struct TMDBCompanySearchResult: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let logoPath: String?
    public let originCountry: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

public struct TMDBCollectionSearchResult: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

private struct TMDBSearchPage<Result: Codable>: Codable {
    let results: [Result]
}

extension TMDBService {
    public func searchCompanies(query: String, page: Int = 1) async throws -> [TMDBCompanySearchResult] {
        let response: TMDBSearchPage<TMDBCompanySearchResult> = try await get(
            path: "/search/company",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
        return response.results
    }

    public func searchCollections(query: String, page: Int = 1) async throws -> [TMDBCollectionSearchResult] {
        let response: TMDBSearchPage<TMDBCollectionSearchResult> = try await get(
            path: "/search/collection",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
        return response.results
    }
}
