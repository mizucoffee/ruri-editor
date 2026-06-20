//
//  EditorRuntimeStore.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class EditorRuntimeStore: ObservableObject {
    struct Key: Hashable {
        let workspaceID: ProjectWorkspaceSnapshot.ID
        let documentID: OpenDocument.ID
    }

    @Published private(set) var findPresentationRequest: EditorFindPresentationRequest?
    @Published private(set) var implementationJumpRequest: EditorImplementationJumpRequest?

    private struct PendingActivationFocusBehavior {
        let targetURL: URL
        let behavior: EditorActivationFocusBehavior
    }

    private var runtimesByKey: [Key: EditorDocumentRuntime] = [:]
    private let syntaxHighlightingService = SyntaxHighlightingService()
    private var pendingActivationFocusBehavior: PendingActivationFocusBehavior?

    deinit {
        MainActor.assumeIsolated {
            runtimesByKey.values.forEach { $0.invalidate() }
        }
    }

    func runtime(
        workspaceID: ProjectWorkspaceSnapshot.ID,
        tab: EditorTabSnapshot,
        session: EditorDocumentSession
    ) -> EditorDocumentRuntime {
        let key = Key(workspaceID: workspaceID, documentID: tab.documentID)

        if let runtime = runtimesByKey[key] {
            runtime.syncExternalTextIfNeeded(tab.text)
            return runtime
        }

        let runtime = EditorDocumentRuntime(
            workspaceID: workspaceID,
            documentID: tab.documentID,
            initialText: tab.text,
            session: session,
            syntaxHighlightingService: syntaxHighlightingService
        )
        runtimesByKey[key] = runtime
        return runtime
    }

    func closeDocument(
        workspaceID: ProjectWorkspaceSnapshot.ID,
        documentID: OpenDocument.ID
    ) {
        let key = Key(workspaceID: workspaceID, documentID: documentID)
        runtimesByKey.removeValue(forKey: key)?.invalidate()
    }

    func closeWorkspace(_ workspaceID: ProjectWorkspaceSnapshot.ID) {
        for key in runtimesByKey.keys where key.workspaceID == workspaceID {
            runtimesByKey.removeValue(forKey: key)?.invalidate()
        }
    }

    func requestActivationFocusBehavior(
        _ behavior: EditorActivationFocusBehavior,
        for targetURL: URL
    ) {
        pendingActivationFocusBehavior = PendingActivationFocusBehavior(
            targetURL: targetURL,
            behavior: behavior
        )
    }

    func activationFocusBehavior(
        for selectedTab: EditorTabSnapshot,
        didChangeSelectedTab: Bool
    ) -> EditorActivationFocusBehavior {
        guard let pendingActivationFocusBehavior else {
            return .preserveIfTextViewFocused
        }

        guard FileURLRewriter.urlsMatch(pendingActivationFocusBehavior.targetURL, selectedTab.url) else {
            if didChangeSelectedTab {
                self.pendingActivationFocusBehavior = nil
            }

            return .preserveIfTextViewFocused
        }

        self.pendingActivationFocusBehavior = nil
        return pendingActivationFocusBehavior.behavior
    }

    func presentFind(showsReplace: Bool) {
        findPresentationRequest = EditorFindPresentationRequest(showsReplace: showsReplace)
    }

    func goToImplementation() {
        implementationJumpRequest = EditorImplementationJumpRequest()
    }
}
