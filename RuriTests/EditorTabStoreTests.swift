//
//  EditorTabStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorTabStoreTests: XCTestCase {
    func testOpenTabReplacesSelectedMainTabWhenRequested() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        let secondDocumentID = URL(filePath: "/tmp/Second.swift")
        var store = EditorTabStore()

        _ = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)
        let result = store.openTab(for: secondDocumentID, replaceSelectedMainTab: true)

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs[0].documentID, secondDocumentID)
        XCTAssertEqual(store.selectedTabID, result.selectedTabID)
        XCTAssertEqual(result.replacedDocumentID, firstDocumentID)
    }

    func testCloseSelectedTabRepairsSelectionToNearbyMainTab() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        let secondDocumentID = URL(filePath: "/tmp/Second.swift")
        let thirdDocumentID = URL(filePath: "/tmp/Third.swift")
        var store = EditorTabStore()

        let first = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)
        let second = store.openTab(for: secondDocumentID, replaceSelectedMainTab: false)
        let third = store.openTab(for: thirdDocumentID, replaceSelectedMainTab: false)
        store.selectTab(second.selectedTabID)

        let result = store.closeTab(second.selectedTabID)

        XCTAssertEqual(result?.closedDocumentID, secondDocumentID)
        XCTAssertEqual(store.selectedTabID, third.selectedTabID)
        XCTAssertNotEqual(store.selectedTabID, first.selectedTabID)
    }

    func testMoveTabReordersTabs() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        let secondDocumentID = URL(filePath: "/tmp/Second.swift")
        let thirdDocumentID = URL(filePath: "/tmp/Third.swift")
        var store = EditorTabStore()

        let first = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)
        _ = store.openTab(for: secondDocumentID, replaceSelectedMainTab: false)
        let third = store.openTab(for: thirdDocumentID, replaceSelectedMainTab: false)

        store.moveTab(first.selectedTabID, to: third.selectedTabID)

        XCTAssertEqual(
            store.tabs.map(\.documentID),
            [secondDocumentID, thirdDocumentID, firstDocumentID]
        )
        XCTAssertEqual(store.selectedTabID, third.selectedTabID)
    }

    func testSelectTabAtShortcutNumberUsesOneBasedTabOrder() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        let secondDocumentID = URL(filePath: "/tmp/Second.swift")
        let thirdDocumentID = URL(filePath: "/tmp/Third.swift")
        var store = EditorTabStore()

        let first = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)
        let second = store.openTab(for: secondDocumentID, replaceSelectedMainTab: false)
        let third = store.openTab(for: thirdDocumentID, replaceSelectedMainTab: false)

        store.selectTab(atShortcutNumber: 1)
        XCTAssertEqual(store.selectedTabID, first.selectedTabID)

        store.selectTab(atShortcutNumber: 2)
        XCTAssertEqual(store.selectedTabID, second.selectedTabID)

        store.selectTab(atShortcutNumber: 3)
        XCTAssertEqual(store.selectedTabID, third.selectedTabID)
    }

    func testSelectTabAtShortcutNumberZeroSelectsLastTab() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        let secondDocumentID = URL(filePath: "/tmp/Second.swift")
        var store = EditorTabStore()

        _ = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)
        let second = store.openTab(for: secondDocumentID, replaceSelectedMainTab: false)
        store.selectTab(atShortcutNumber: 1)

        store.selectTab(atShortcutNumber: 0)

        XCTAssertEqual(store.selectedTabID, second.selectedTabID)
    }

    func testSelectTabAtShortcutNumberOutOfRangeDoesNothing() {
        let firstDocumentID = URL(filePath: "/tmp/First.swift")
        var store = EditorTabStore()

        let first = store.openTab(for: firstDocumentID, replaceSelectedMainTab: false)

        store.selectTab(atShortcutNumber: 2)

        XCTAssertEqual(store.selectedTabID, first.selectedTabID)
    }
}
