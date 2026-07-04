//
//  CodingAgentStatusNotifier.swift
//  ruri
//

import Foundation
import UserNotifications

nonisolated protocol CodingAgentStatusNotifying: Sendable {
    func notify(status: CodingAgentStatus, context: CodingAgentNotificationContext) async
    func removeDeliveredNotifications(forTerminalIDs terminalIDs: Set<TerminalTab.ID>) async
}

nonisolated struct CodingAgentNotificationContext: Equatable, Sendable {
    let terminalTitle: String
    let workspaceName: String?
}

nonisolated struct CodingAgentStatusNotifier: CodingAgentStatusNotifying, Sendable {
    nonisolated init() {}

    nonisolated func notify(status: CodingAgentStatus, context: CodingAgentNotificationContext) async {
        guard status.state.isNotificationEligible else { return }

        let center = UNUserNotificationCenter.current()
        guard await requestAuthorizationIfNeeded(center: center) else {
            return
        }

        await removeDeliveredNotifications(forTerminalIDs: [status.terminalID])

        let content = UNMutableNotificationContent()
        content.title = "\(status.provider.displayName) \(status.state.notificationTitle(for: status.event))"
        if let workspaceName = context.workspaceName {
            content.subtitle = workspaceName
        }
        content.body = body(for: status, context: context)
        content.sound = .default
        content.userInfo = [
            CodingAgentNotificationUserInfoKey.kind: CodingAgentNotificationUserInfoValue.kind,
            CodingAgentNotificationUserInfoKey.terminalID: status.terminalID.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "coding-agent-\(status.terminalID.uuidString)-\(status.changeKey.stableNotificationIdentifierSuffix)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    nonisolated func removeDeliveredNotifications(forTerminalIDs terminalIDs: Set<TerminalTab.ID>) async {
        guard !terminalIDs.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let terminalIDStrings = Set(terminalIDs.map(\.uuidString))
        let identifiers = await center.deliveredNotifications()
            .filter { notification in
                let userInfo = notification.request.content.userInfo
                guard userInfo[CodingAgentNotificationUserInfoKey.kind] as? String
                        == CodingAgentNotificationUserInfoValue.kind,
                      let terminalID = userInfo[CodingAgentNotificationUserInfoKey.terminalID] as? String else {
                    return false
                }
                return terminalIDStrings.contains(terminalID)
            }
            .map(\.request.identifier)

        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private nonisolated func requestAuthorizationIfNeeded(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        @unknown default:
            return false
        }
    }

    private nonisolated func body(
        for status: CodingAgentStatus,
        context: CodingAgentNotificationContext
    ) -> String {
        var details = [status.event.notificationEventDescription]
        if !context.terminalTitle.isEmpty {
            details.append("Terminal: \(context.terminalTitle)")
        }
        return details.joined(separator: "\n")
    }
}

enum CodingAgentNotificationUserInfoKey {
    static let kind = "kind"
    static let terminalID = "terminalID"
}

enum CodingAgentNotificationUserInfoValue {
    static let kind = "codingAgentStatus"
}

private extension CodingAgentState {
    nonisolated func notificationTitle(for event: String) -> String {
        switch self {
        case .running:
            "is running"
        case .waiting:
            event == "PermissionRequest" ? "needs permission" : "needs attention"
        case .completed:
            "finished"
        case .error:
            "hit an error"
        }
    }
}

private extension String {
    nonisolated var notificationEventDescription: String {
        switch self {
        case "UserPromptSubmit":
            "Prompt submitted."
        case "PreToolUse":
            "Tool execution started."
        case "PermissionRequest":
            "A tool is waiting for your approval."
        case "PostToolUse":
            "Tool execution finished."
        case "PostToolUseFailure":
            "Tool execution failed."
        case "Stop":
            "The coding agent session completed."
        case "StopFailure":
            "The coding agent failed while stopping."
        case "":
            "Status changed."
        default:
            "Event: \(self)"
        }
    }

    nonisolated var stableNotificationIdentifierSuffix: String {
        unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }
        .joined()
    }
}
