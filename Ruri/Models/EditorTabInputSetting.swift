//
//  EditorTabInputSetting.swift
//  ruri
//

import Combine
import Foundation

struct EditorTabInputSetting: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case spaces
        case tabs

        var displayName: String {
            switch self {
            case .spaces:
                "Spaces"
            case .tabs:
                "Tabs"
            }
        }
    }

    static let allowedWidths = [2, 4, 8]
    static let defaultValue = EditorTabInputSetting(mode: .spaces, width: 4)

    let mode: Mode
    let width: Int

    init(mode: Mode, width: Int) {
        self.mode = mode
        self.width = Self.allowedWidths.contains(width) ? width : Self.defaultValue.width
    }

    init?(identifier: String) {
        let components = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let mode = Mode(rawValue: components[0]),
              let width = Int(components[1]),
              Self.allowedWidths.contains(width) else {
            return nil
        }

        self.init(mode: mode, width: width)
    }

    var identifier: String {
        "\(mode.rawValue):\(width)"
    }

    var displayText: String {
        "\(mode.displayName): \(width)"
    }

    var indentationUnit: String {
        switch mode {
        case .spaces:
            String(repeating: " ", count: width)
        case .tabs:
            "\t"
        }
    }

    static var menuOptions: [EditorTabInputSetting] {
        Mode.allCases.flatMap { mode in
            allowedWidths.map { width in
                EditorTabInputSetting(mode: mode, width: width)
            }
        }
    }
}

@MainActor
final class EditorTabInputSettingsStore: ObservableObject {
    static let modeDefaultsKey = "ruri.editor.tabInput.mode"
    static let widthDefaultsKey = "ruri.editor.tabInput.width"

    @Published var setting: EditorTabInputSetting {
        didSet {
            guard !isApplyingDefaultsUpdate,
                  oldValue != setting else {
                return
            }

            save(setting)
        }
    }

    private let userDefaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?
    private var isApplyingDefaultsUpdate = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        setting = Self.loadSetting(from: userDefaults)

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

    private func reloadFromDefaults() {
        let loadedSetting = Self.loadSetting(from: userDefaults)
        guard loadedSetting != setting else { return }

        isApplyingDefaultsUpdate = true
        setting = loadedSetting
        isApplyingDefaultsUpdate = false
    }

    private func save(_ setting: EditorTabInputSetting) {
        userDefaults.set(setting.mode.rawValue, forKey: Self.modeDefaultsKey)
        userDefaults.set(setting.width, forKey: Self.widthDefaultsKey)
    }

    private static func loadSetting(from userDefaults: UserDefaults) -> EditorTabInputSetting {
        guard let modeRawValue = userDefaults.string(forKey: modeDefaultsKey),
              let mode = EditorTabInputSetting.Mode(rawValue: modeRawValue) else {
            return .defaultValue
        }

        let width = userDefaults.integer(forKey: widthDefaultsKey)
        guard EditorTabInputSetting.allowedWidths.contains(width) else {
            return .defaultValue
        }

        return EditorTabInputSetting(mode: mode, width: width)
    }
}
