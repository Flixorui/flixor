//
//  HomeViewModel+Rows.swift
//  FlixorMac
//
//  Row titles and captions for the home screen.
//

import Foundation

extension HomeViewModel {
    /// Captions for rows whose (final) title is shared with another row.
    /// Only Stremio catalog rows get one: the addon name they come from.
    func duplicateTitleCaptions(for rows: [(id: String, title: String)]) -> [String: String] {
        var counts: [String: Int] = [:]
        for row in rows {
            counts[normalizedTitle(row.title), default: 0] += 1
        }
        var captions: [String: String] = [:]
        for row in rows where (counts[normalizedTitle(row.title)] ?? 0) > 1 {
            if let addon = catalogAddonNames[row.id] {
                captions[row.id] = addon
            }
        }
        return captions
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
