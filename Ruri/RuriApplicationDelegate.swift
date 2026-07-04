//
//  RuriApplicationDelegate.swift
//  ruri
//
//  Created by Codex on 2026/06/17.
//

import AppKit
import UserNotifications

@MainActor
final class RuriApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        RuriApplicationTerminationCoordinator.shared.applicationShouldTerminate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                await ExternalGitHubPullRequestURLRouter.shared.open(url)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            CodingAgentNotificationRouter.shared.openNotification(
                userInfo: response.notification.request.content.userInfo
            )
            completionHandler()
        }
    }
}
