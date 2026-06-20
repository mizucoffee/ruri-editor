//
//  GitHubAuthModels.swift
//  ruri
//

import Foundation

enum GitHubAuthStatusState: Equatable, Sendable {
    case checking
    case authenticating
    case authenticated(username: String)
    case unauthenticated
    case unavailable(message: String)
    case failed(message: String)
}

struct GitHubLoginDevicePrompt: Equatable, Sendable {
    let userCode: String
    let verificationURL: URL
}
