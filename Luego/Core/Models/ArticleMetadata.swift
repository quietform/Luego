//
//  ArticleMetadata.swift
//  Luego
//
//  Created by Claude on 2025-11-10.
//

import Foundation

struct ArticleMetadata {
    let title: String
    let thumbnailURL: URL?
    let description: String?
    let publishedDate: Date?
    let wordCount: Int?

    init(
        title: String,
        thumbnailURL: URL? = nil,
        description: String? = nil,
        publishedDate: Date? = nil,
        wordCount: Int? = nil
    ) {
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.publishedDate = publishedDate
        self.wordCount = wordCount
    }
}

struct LuegoAPIResponse: Decodable {
    let content: String
    let metadata: LuegoAPIMetadata
}

struct LuegoAPIMetadata: Decodable {
    let title: String?
    let author: String?
    let publishedDate: String?
    let estimatedReadTimeMinutes: Int?
    let wordCount: Int?
    let sourceUrl: String
    let domain: String
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case title, author, domain, thumbnail
        case publishedDate = "published_date"
        case estimatedReadTimeMinutes = "estimated_read_time_minutes"
        case wordCount = "word_count"
        case sourceUrl = "source_url"
    }
}

enum LuegoAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case unauthorized
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .decodingError:
            return "Failed to parse API response"
        case .unauthorized:
            return "Invalid API key"
        case .serviceUnavailable:
            return "API service unavailable"
        }
    }
}

enum ArticleMetadataError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(Error)
    case noMetadata

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL provided is not valid"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError:
            return "Failed to parse the article content"
        case .noMetadata:
            return "Could not find article metadata"
        }
    }
}
