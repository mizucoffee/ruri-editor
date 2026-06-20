//
//  ProjectWindowRequest.swift
//  ruri
//
//  Created by Codex on 2026/06/17.
//

import Foundation

struct ProjectWindowRequest: Codable, Hashable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }
}
