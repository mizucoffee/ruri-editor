//
//  EditorLineWrappingSettingsStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorLineWrappingSettingsStoreTests: XCTestCase {
    func testDefaultsToWrappedWhenUnset() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }

        let store = EditorLineWrappingSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.mode, .defaultValue)
        XCTAssertTrue(store.mode.isWrappingEnabled)
    }

    func testPersistsSelectedMode() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }
        var store: EditorLineWrappingSettingsStore? = EditorLineWrappingSettingsStore(userDefaults: defaults)

        store?.mode = .unwrapped
        store = nil

        let reloadedStore = EditorLineWrappingSettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.mode, .unwrapped)
        XCTAssertFalse(reloadedStore.mode.isWrappingEnabled)
    }

    func testInvalidStoredValueFallsBackToWrapped() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }
        defaults.set("invalid", forKey: EditorLineWrappingSettingsStore.modeDefaultsKey)

        let store = EditorLineWrappingSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.mode, .defaultValue)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ruri.EditorLineWrappingSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "_ruriTestSuiteName")
        return defaults
    }

    private func removeUserDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "_ruriTestSuiteName") else {
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
    }
}
