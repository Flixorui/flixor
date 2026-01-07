//
//  MDBListRatings.swift
//  FlixorMac
//
//  MDBList ratings aggregation model
//

import Foundation
import SwiftUI

struct MDBListRatings: Codable {
    var imdb: Double?
    var tmdb: Double?
    var trakt: Double?
    var letterboxd: Double?
    var tomatoes: Double?      // RT Critics
    var audience: Double?      // RT Audience
    var metacritic: Double?

    var hasAnyRating: Bool {
        return imdb != nil || tmdb != nil || trakt != nil ||
               letterboxd != nil || tomatoes != nil ||
               audience != nil || metacritic != nil
    }
}

struct RatingProvider {
    let name: String
    let color: Color
}

let RATING_PROVIDERS: [String: RatingProvider] = [
    "imdb": RatingProvider(name: "IMDb", color: Color(hex: "F5C518")),
    "tmdb": RatingProvider(name: "TMDB", color: Color(hex: "01B4E4")),
    "trakt": RatingProvider(name: "Trakt", color: Color(hex: "ED1C24")),
    "letterboxd": RatingProvider(name: "Letterboxd", color: Color(hex: "00E054")),
    "tomatoes": RatingProvider(name: "Rotten Tomatoes", color: Color(hex: "FA320A")),
    "audience": RatingProvider(name: "Audience Score", color: Color(hex: "FA320A")),
    "metacritic": RatingProvider(name: "Metacritic", color: Color(hex: "FFCC33"))
]
