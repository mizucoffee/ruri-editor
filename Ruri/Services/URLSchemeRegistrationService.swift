//
//  URLSchemeRegistrationService.swift
//  ruri
//
//  Created by Codex on 2026/06/17.
//

import CoreServices
import Foundation

enum URLSchemeRegistrationService {
    static func registerDefaultHandlers() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        LSSetDefaultHandlerForURLScheme("ruri" as CFString, bundleIdentifier as CFString)
    }
}
