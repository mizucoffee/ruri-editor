//
//  EditorTabInputSettingsStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorTabInputSettingsStoreTests: XCTestCase {
    func testDefaultsToSpacesFourWhenUnset() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }

        let store = EditorTabInputSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.setting, .defaultValue)
    }

    func testPersistsSelectedSetting() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }
        var store: EditorTabInputSettingsStore? = EditorTabInputSettingsStore(userDefaults: defaults)

        store?.setting = EditorTabInputSetting(mode: .tabs, width: 8)
        store = nil

        let reloadedStore = EditorTabInputSettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.setting, EditorTabInputSetting(mode: .tabs, width: 8))
    }

    func testInvalidStoredValuesFallBackToSpacesFour() {
        let defaults = makeUserDefaults()
        defer { removeUserDefaults(defaults) }
        defaults.set("tabs", forKey: EditorTabInputSettingsStore.modeDefaultsKey)
        defaults.set(3, forKey: EditorTabInputSettingsStore.widthDefaultsKey)

        let store = EditorTabInputSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.setting, .defaultValue)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ruri.EditorTabInputSettingsStoreTests.\(UUID().uuidString)"
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
