//
//  ReviewDiffState.swift
//  ruri
//

import Foundation

nonisolated enum ReviewDiffState: Equatable, Sendable {
    case unavailable
    case loading
    case loaded(GitReviewDiffSnapshot)
    case failed(String)
}
