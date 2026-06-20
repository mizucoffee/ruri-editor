//
//  EditorLineWrappingMode.swift
//  ruri
//

import Combine
import Foundation

enum EditorLineWrappingMode: String, Sendable {
    case wrapped
    case unwrapped

    static let defaultValue = EditorLineWrappingMode.wrapped

    var isWrappingEnabled: Bool {
        self == .wrapped
    }
}

@MainActor
final class EditorLineWrappingSettingsStore: ObservableObject {
    static let modeDefaultsKey = "ruri.editor.lineWrapping.mode"

    @Published var mode: EditorLineWrappingMode {
        didSet {
            guard !isApplyingDefaultsUpdate,
                  oldValue != mode else {
                return
            }

            save(mode)
        }
    }

    private let userDefaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?
    private var isApplyingDefaultsUpdate = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        mode = Self.loadMode(from: userDefaults)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromDefaults()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func setWrappingEnabled(_ isEnabled: Bool) {
        mode = isEnabled ? .wrapped : .unwrapped
    }

    private func reloadFromDefaults() {
        let loadedMode = Self.loadMode(from: userDefaults)
        guard loadedMode != mode else { return }

        isApplyingDefaultsUpdate = true
        mode = loadedMode
        isApplyingDefaultsUpdate = false
    }

    private func save(_ mode: EditorLineWrappingMode) {
        userDefaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
    }

    private static func loadMode(from userDefaults: UserDefaults) -> EditorLineWrappingMode {
        guard let rawValue = userDefaults.string(forKey: modeDefaultsKey),
              let mode = EditorLineWrappingMode(rawValue: rawValue) else {
            return .defaultValue
        }

        return mode
    }
}
