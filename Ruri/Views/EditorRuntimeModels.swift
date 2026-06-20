//
//  EditorRuntimeModels.swift
//  ruri
//

import Foundation

struct EditorFindPresentationRequest: Equatable {
    let id = UUID()
    let showsReplace: Bool
}

struct EditorImplementationJumpRequest: Equatable {
    let id = UUID()
}

enum EditorActivationFocusBehavior {
    case preserveIfTextViewFocused
    case focusTextView
    case keepCurrentFocus
}

struct EditorUndoCommandState: Equatable {
    var canUndo = false
    var canRedo = false
    var undoActionName = ""
    var redoActionName = ""
}

struct EditorFindState: Equatable {
    var isPresented = false
    var showsReplace = false
    var query = ""
    var replacement = ""
    var isRegex = false
    var isCaseSensitive = false
    var matches: [NSRange] = []
    var selectedMatchIndex: Int?
    var errorMessage: String?

    var canNavigate: Bool {
        errorMessage == nil && !matches.isEmpty
    }

    var canReplace: Bool {
        canNavigate && selectedMatchIndex != nil
    }

    var canReplaceAll: Bool {
        canNavigate
    }

    var matchDescription: String {
        if let errorMessage {
            return errorMessage
        }

        guard !query.isEmpty else {
            return ""
        }

        guard !matches.isEmpty else {
            return "No matches"
        }

        guard let selectedMatchIndex else {
            return "\(matches.count) matches"
        }

        return "\(selectedMatchIndex + 1) of \(matches.count)"
    }
}

struct EditorCursorPosition: Equatable {
    var line: Int
    var column: Int

    var displayText: String {
        "Ln \(line), Col \(column)"
    }
}

struct EditorSyntaxLanguageState: Equatable {
    let inferredLanguageName: String?
    let overrideLanguageName: String?
    let languageOptions: [SyntaxLanguageOption]

    var autoDisplayName: String {
        SyntaxLanguageResolver.autoDisplayName(for: inferredLanguageName)
    }

    var selectedLanguageName: String? {
        overrideLanguageName
    }

    var effectiveLanguageName: String? {
        overrideLanguageName ?? inferredLanguageName
    }

    var effectiveDisplayName: String {
        guard let effectiveLanguageName else { return "Auto Detect" }
        return SyntaxLanguageResolver.displayName(for: effectiveLanguageName)
    }
}

@MainActor
protocol EditorDocumentRuntimeDelegate: AnyObject {
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeText text: String)
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeSelection selectedRange: NSRange)
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeScrollOrigin scrollOrigin: CGPoint)
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeFindState findState: EditorFindState)
    func editorDocumentRuntimeDidRequestFindFocus(_ runtime: EditorDocumentRuntime)
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didRequestImplementationJumpAt utf16Offset: Int)
    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, implementationHoverRangeAt utf16Offset: Int) async -> NSRange?
}
