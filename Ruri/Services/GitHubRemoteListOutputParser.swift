//
//  GitHubRemoteListOutputParser.swift
//  ruri
//

import Foundation

nonisolated enum GitHubRemoteListOutputParser {
    static func parse(_ output: String) -> [GitHubRepositoryIdentity] {
        var identities: [GitHubRepositoryIdentity] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                  let identity = identity(from: String(fields[1])),
                  !identities.contains(where: { $0.matches(identity) }) else {
                continue
            }

            identities.append(identity)
        }

        return identities
    }

    private static func identity(from remoteURL: String) -> GitHubRepositoryIdentity? {
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmedURL),
           components.host?.lowercased() == "github.com" {
            return identity(fromPath: components.path)
        }

        let sshPrefix = "git@github.com:"
        if trimmedURL.hasPrefix(sshPrefix) {
            return identity(fromPath: String(trimmedURL.dropFirst(sshPrefix.count)))
        }

        return nil
    }

    private static func identity(fromPath path: String) -> GitHubRepositoryIdentity? {
        var trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.hasSuffix(".git") {
            trimmedPath.removeLast(4)
        }
        let components = trimmedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2 else { return nil }

        return GitHubRepositoryIdentity(owner: String(components[0]), name: String(components[1]))
    }
}
