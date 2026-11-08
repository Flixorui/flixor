//
//  OpenSubtitlesHasher.swift
//  FlixorMac
//
//  OpenSubtitles "moviehash" for remote video files, computed with two HTTP
//  range requests (first and last 64 KB). Subtitle addons use it to return
//  subtitles synced to the exact release.
//

import Foundation

struct OpenSubtitlesHash: Equatable {
    /// 16 lowercase hex digits.
    let hash: String
    /// File size in bytes.
    let size: Int64
}

enum OpenSubtitlesHasher {
    static let chunkSize = 65_536

    /// Hash of the file at `url`, or nil when it can't be computed cheaply: the
    /// server ignores Range requests (it would send the whole file), reports no
    /// size, the file is smaller than 64 KB, or a request fails/times out.
    /// Never downloads more than 2 × 64 KB.
    static func hash(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 10) async -> OpenSubtitlesHash? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        guard let head = await fetchRange(session: session, url: url, headers: headers, range: "bytes=0-\(chunkSize - 1)"),
              let size = head.totalSize, size >= Int64(chunkSize), head.data.count == chunkSize else {
            return nil
        }
        let tailStart = size - Int64(chunkSize)
        guard let tail = await fetchRange(session: session, url: url, headers: headers, range: "bytes=\(tailStart)-\(size - 1)"),
              tail.data.count == chunkSize else {
            return nil
        }
        return OpenSubtitlesHash(hash: compute(size: size, head: head.data, tail: tail.data), size: size)
    }

    /// moviehash = file size + sum of the first and last 64 KB read as
    /// little-endian UInt64 words, all with wrapping (overflowing) addition.
    static func compute(size: Int64, head: Data, tail: Data) -> String {
        var sum = UInt64(bitPattern: size)
        for chunk in [head, tail] {
            chunk.withUnsafeBytes { raw in
                let words = raw.count / 8
                for i in 0..<words {
                    sum &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
                }
            }
        }
        return String(format: "%016llx", sum)
    }

    private struct RangeResult {
        let data: Data
        let totalSize: Int64?
    }

    /// GETs one byte range. Bails out (cancelling the transfer) unless the server
    /// answers 206 Partial Content, so a server without range support never
    /// streams the whole file.
    private static func fetchRange(session: URLSession, url: URL, headers: [String: String], range: String) async -> RangeResult? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue(range, forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
                bytes.task.cancel()
                return nil
            }
            // "Content-Range: bytes 0-65535/123456789"
            let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            let total = contentRange.split(separator: "/").last.flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
            var data = Data()
            data.reserveCapacity(chunkSize)
            for try await byte in bytes {
                data.append(byte)
                if data.count >= chunkSize { break }
            }
            bytes.task.cancel()
            return RangeResult(data: data, totalSize: total)
        } catch {
            return nil
        }
    }
}
