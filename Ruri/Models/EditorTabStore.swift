//
//  EditorTabStore.swift
//  ruri
//

import Foundation

struct EditorTabStore {
    struct OpenResult: Equatable {
        let selectedTabID: EditorTab.ID
        let replacedDocumentID: OpenDocument.ID?
    }

    struct CloseResult: Equatable {
        let closedDocumentID: OpenDocument.ID
    }

    private(set) var tabs: [EditorTab] = []
    private(set) var selectedTabID: EditorTab.ID?

    var mainTabs: [EditorTab] {
        tabs
    }

    mutating func reset() {
        tabs = []
        selectedTabID = nil
    }

    func tab(for id: EditorTab.ID) -> EditorTab? {
        tabs.first { $0.id == id }
    }

    func tab(containing documentID: OpenDocument.ID) -> EditorTab? {
        tabs.first { $0.documentID == documentID }
    }

    func selectedMainTab() -> EditorTab? {
        guard let selectedTabID,
              let tab = tab(for: selectedTabID) else {
            return nil
        }

        return tab
    }

    mutating func selectTab(_ id: EditorTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    mutating func openTab(
        for documentID: OpenDocument.ID,
        replaceSelectedMainTab: Bool
    ) -> OpenResult {
        if let existingIndex = tabs.firstIndex(where: { $0.documentID == documentID }) {
            selectedTabID = tabs[existingIndex].id
            return OpenResult(selectedTabID: tabs[existingIndex].id, replacedDocumentID: nil)
        }

        let tab = EditorTab(documentID: documentID)

        if replaceSelectedMainTab,
           let selectedIndex = selectedMainTabIndex {
            let replacedDocumentID = tabs[selectedIndex].documentID
            tabs[selectedIndex] = tab
            selectedTabID = tab.id
            return OpenResult(selectedTabID: tab.id, replacedDocumentID: replacedDocumentID)
        }

        tabs.append(tab)
        selectedTabID = tab.id
        return OpenResult(selectedTabID: tab.id, replacedDocumentID: nil)
    }

    mutating func closeTab(_ id: EditorTab.ID) -> CloseResult? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }

        let closedDocumentID = tabs[index].documentID
        let wasSelected = selectedTabID == id
        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedTabID = nil
        } else if wasSelected || selectedTabIDNeedsRepair {
            selectMainTabNear(index)
        }

        return CloseResult(closedDocumentID: closedDocumentID)
    }

    mutating func moveTab(_ movingID: EditorTab.ID, to targetID: EditorTab.ID) {
        guard movingID != targetID,
              let movingIndex = tabs.firstIndex(where: { $0.id == movingID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let tab = tabs.remove(at: movingIndex)
        let updatedTargetIndex = tabs.firstIndex { $0.id == targetID } ?? targetIndex
        let insertionIndex = targetIndex > movingIndex ? updatedTargetIndex + 1 : updatedTargetIndex
        tabs.insert(tab, at: insertionIndex)
    }

    mutating func rewriteDocumentIDs(_ documentIDMapping: [OpenDocument.ID: OpenDocument.ID]) {
        guard !documentIDMapping.isEmpty else { return }

        for index in tabs.indices {
            if let rewrittenDocumentID = documentIDMapping[tabs[index].documentID] {
                tabs[index].documentID = rewrittenDocumentID
            }
        }
    }

    private var selectedMainTabIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    private var selectedTabIDNeedsRepair: Bool {
        guard let selectedTabID else { return false }
        return !tabs.contains { $0.id == selectedTabID }
    }

    private mutating func selectMainTabNear(_ index: Int) {
        guard !mainTabs.isEmpty else {
            selectedTabID = nil
            return
        }

        let nextTab = tabs.enumerated().first { candidateIndex, _ in
            candidateIndex >= index
        }?.element ?? tabs.last

        selectedTabID = nextTab?.id
    }
}
