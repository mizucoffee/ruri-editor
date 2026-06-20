//
//  RuriApp.swift
//  ruri
//
//  Created by mizucoffee on 2026/06/08.
//

import SwiftUI

@main
struct ruriApp: App {
    @NSApplicationDelegateAdaptor(RuriApplicationDelegate.self) private var applicationDelegate

    init() {
        URLSchemeRegistrationService.registerDefaultHandlers()
    }

    var body: some Scene {
        WindowGroup("ruri", for: ProjectWindowRequest.self) { request in
            RuriWindowRoot(initialProjectURL: request.wrappedValue?.url)
        }
        .commands {
            AppCommands()
        }
    }
}
