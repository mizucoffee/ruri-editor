//
//  EditorPaneHostView.swift
//  ruri
//

import AppKit
import SwiftUI

struct EditorPaneHostView: NSViewControllerRepresentable {
    let workspaceID: ProjectWorkspaceSnapshot.ID?
    let editorMode: EditorMode
    let reviewDiffState: ReviewDiffState
    let reviewDiffBase: GitReviewDiffBase?
    let reviewDiffRemoteBranches: [GitRemoteBranchInfo]
    let isLoadingReviewDiffRemoteBranches: Bool
    let reviewDiffRemoteBranchErrorMessage: String?
    let reviewDiffHideWhitespace: Bool
    @Binding var reviewDiffDisplayMode: ReviewDiffDisplayMode
    @Binding var reviewDiffWrapLines: Bool
    let runtimeStore: EditorRuntimeStore
    let tabs: [EditorTabSnapshot]
    let selectedTabID: EditorTab.ID?
    let findPresentationRequest: EditorFindPresentationRequest?
    let implementationJumpRequest: EditorImplementationJumpRequest?
    let symbolIndexStatus: SymbolIndexStatusState
    let fileSearchIndexStatus: ProjectFileSearchIndexStatusState
    let gitRepositoryStatus: GitRepositoryStatus
    let gitSnapshot: GitRepositorySnapshot?
    let githubAuthStatus: GitHubAuthStatusState
    let githubPullRequestStatus: GitHubPullRequestStatus?
    let tabInputSetting: EditorTabInputSetting
    let lineWrappingMode: EditorLineWrappingMode
    let editorSession: (EditorTab.ID) -> EditorDocumentSession?
    let updateText: (String, EditorTab.ID) -> Void
    let updateSelection: (NSRange, EditorTab.ID) -> Void
    let updateScrollOrigin: (CGPoint, EditorTab.ID) -> Void
    let requestImplementationJump: (EditorTab.ID, Int) -> Void
    let implementationHoverRange: (EditorTab.ID, Int) async -> NSRange?
    let requestReviewDiffCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let reviewDiffCodeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    let selectTab: (EditorTab.ID) -> Void
    let setTabInputSetting: (EditorTabInputSetting) -> Void
    let switchGitBranch: (String) -> Void
    let refreshGitHubAuthStatus: () -> Void
    let logInToGitHub: () -> Void
    let openGitHubPullRequest: (URL) -> Void
    let selectReviewDiffBase: (GitReviewDiffBase) -> Void
    let loadReviewDiffRemoteBranches: (Bool) -> Void
    let refreshReviewDiff: () -> Void
    let setReviewDiffHideWhitespace: (Bool) -> Void
    let openReviewDiffFile: (URL) -> Void
    let closeTab: (EditorTab.ID) -> Void
    let moveTab: (EditorTab.ID, EditorTab.ID) -> Void
    let terminalWorkspaceURL: URL?
    let terminalTabs: [TerminalTabSnapshot]
    let selectedTerminalTabID: TerminalTab.ID?
    let terminalFocusRequest: TerminalFocusRequest?
    let isTerminalMinimized: Bool
    let terminalView: (TerminalTab.ID) -> NSView?
    let createTerminalTab: () -> Void
    let selectTerminalTab: (TerminalTab.ID) -> Void
    let closeTerminalTab: (TerminalTab.ID) -> Void
    let toggleTerminalMinimized: () -> Void

    func makeNSViewController(context: Context) -> EditorPaneViewController {
        EditorPaneViewController(runtimeStore: runtimeStore)
    }

    func updateNSViewController(_ viewController: EditorPaneViewController, context: Context) {
        viewController.update(
            workspaceID: workspaceID,
            editorMode: editorMode,
            reviewDiffState: reviewDiffState,
            reviewDiffBase: reviewDiffBase,
            reviewDiffRemoteBranches: reviewDiffRemoteBranches,
            isLoadingReviewDiffRemoteBranches: isLoadingReviewDiffRemoteBranches,
            reviewDiffRemoteBranchErrorMessage: reviewDiffRemoteBranchErrorMessage,
            reviewDiffHideWhitespace: reviewDiffHideWhitespace,
            reviewDiffDisplayMode: $reviewDiffDisplayMode,
            reviewDiffWrapLines: $reviewDiffWrapLines,
            tabs: tabs,
            selectedTabID: selectedTabID,
            findPresentationRequest: findPresentationRequest,
            implementationJumpRequest: implementationJumpRequest,
            symbolIndexStatus: symbolIndexStatus,
            fileSearchIndexStatus: fileSearchIndexStatus,
            gitRepositoryStatus: gitRepositoryStatus,
            gitSnapshot: gitSnapshot,
            githubAuthStatus: githubAuthStatus,
            githubPullRequestStatus: githubPullRequestStatus,
            tabInputSetting: tabInputSetting,
            lineWrappingMode: lineWrappingMode,
            editorSession: editorSession,
            updateText: updateText,
            updateSelection: updateSelection,
            updateScrollOrigin: updateScrollOrigin,
            requestImplementationJump: requestImplementationJump,
            implementationHoverRange: implementationHoverRange,
            requestReviewDiffCodeNavigation: requestReviewDiffCodeNavigation,
            reviewDiffCodeNavigationHoverRange: reviewDiffCodeNavigationHoverRange,
            selectTab: selectTab,
            setTabInputSetting: setTabInputSetting,
            switchGitBranch: switchGitBranch,
            refreshGitHubAuthStatus: refreshGitHubAuthStatus,
            logInToGitHub: logInToGitHub,
            openGitHubPullRequest: openGitHubPullRequest,
            selectReviewDiffBase: selectReviewDiffBase,
            loadReviewDiffRemoteBranches: loadReviewDiffRemoteBranches,
            refreshReviewDiff: refreshReviewDiff,
            setReviewDiffHideWhitespace: setReviewDiffHideWhitespace,
            openReviewDiffFile: openReviewDiffFile,
            closeTab: closeTab,
            moveTab: moveTab,
            terminalWorkspaceURL: terminalWorkspaceURL,
            terminalTabs: terminalTabs,
            selectedTerminalTabID: selectedTerminalTabID,
            terminalFocusRequest: terminalFocusRequest,
            isTerminalMinimized: isTerminalMinimized,
            terminalView: terminalView,
            createTerminalTab: createTerminalTab,
            selectTerminalTab: selectTerminalTab,
            closeTerminalTab: closeTerminalTab,
            toggleTerminalMinimized: toggleTerminalMinimized
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: EditorPaneViewController,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}

@MainActor
final class EditorPaneViewController: NSViewController, EditorDocumentRuntimeDelegate, NSSplitViewDelegate {
    private let runtimeStore: EditorRuntimeStore
    private let splitView = NSSplitView()
    private let editorContainerView = NSView()
    private let tabBarView = EditorTabBarView()
    private let tabSeparator = NSBox()
    private let findBarView = EditorFindBarAppKitView()
    private let findSeparator = NSBox()
    private let bodyContainerView = EditorBodyContainerAppKitView()
    private let editorStatusSeparator = NSBox()
    private let editorStatusBarView = EditorStatusBarAppKitView()
    private let emptyView = EditorEmptyAppKitView()
    private let terminalPanelView = TerminalPanelAppKitView()
    private var reviewDiffHostingView: NSHostingView<ReviewDiffView>?

    private var workspaceID: ProjectWorkspaceSnapshot.ID?
    private var editorMode = EditorMode.edit
    private var reviewDiffState = ReviewDiffState.unavailable
    private var reviewDiffBase: GitReviewDiffBase?
    private var reviewDiffRemoteBranches: [GitRemoteBranchInfo] = []
    private var isLoadingReviewDiffRemoteBranches = false
    private var reviewDiffRemoteBranchErrorMessage: String?
    private var reviewDiffHideWhitespace = false
    private var reviewDiffDisplayMode: Binding<ReviewDiffDisplayMode>?
    private var reviewDiffWrapLines: Binding<Bool>?
    private var tabs: [EditorTabSnapshot] = []
    private var selectedTabID: EditorTab.ID?
    private var activeRuntime: EditorDocumentRuntime?
    private var consumedFindPresentationRequestID: UUID?
    private var consumedImplementationJumpRequestID: UUID?
    private var consumedTerminalFocusRequestID: UUID?
    private var symbolIndexStatus = SymbolIndexStatusState.inactive
    private var fileSearchIndexStatus = ProjectFileSearchIndexStatusState.inactive
    private var gitRepositoryStatus = GitRepositoryStatus.inactive
    private var gitSnapshot: GitRepositorySnapshot?
    private var githubAuthStatus = GitHubAuthStatusState.checking
    private var githubPullRequestStatus: GitHubPullRequestStatus?
    private var tabInputSetting = EditorTabInputSetting.defaultValue
    private var lineWrappingMode = EditorLineWrappingMode.defaultValue
    private var isTerminalMinimized = false
    private var terminalStatus = TerminalStatusBarState(tabCount: 0, isMinimized: false, isEnabled: false)
    private var lastTerminalHeight: CGFloat?
    private var shouldApplyTerminalSplit = true
    private var isApplyingTerminalSplit = false

    private var editorSession: ((EditorTab.ID) -> EditorDocumentSession?)?
    private var updateText: ((String, EditorTab.ID) -> Void)?
    private var updateSelection: ((NSRange, EditorTab.ID) -> Void)?
    private var updateScrollOrigin: ((CGPoint, EditorTab.ID) -> Void)?
    private var requestImplementationJump: ((EditorTab.ID, Int) -> Void)?
    private var implementationHoverRange: ((EditorTab.ID, Int) async -> NSRange?)?
    private var selectTab: ((EditorTab.ID) -> Void)?
    private var setTabInputSetting: ((EditorTabInputSetting) -> Void)?
    private var switchGitBranch: ((String) -> Void)?
    private var refreshGitHubAuthStatus: (() -> Void)?
    private var logInToGitHub: (() -> Void)?
    private var openGitHubPullRequest: ((URL) -> Void)?
    private var selectReviewDiffBase: ((GitReviewDiffBase) -> Void)?
    private var loadReviewDiffRemoteBranches: ((Bool) -> Void)?
    private var refreshReviewDiff: (() -> Void)?
    private var setReviewDiffHideWhitespace: ((Bool) -> Void)?
    private var openReviewDiffFile: ((URL) -> Void)?
    private var closeTab: ((EditorTab.ID) -> Void)?
    private var moveTab: ((EditorTab.ID, EditorTab.ID) -> Void)?
    private var toggleTerminalMinimized: (() -> Void)?

    init(runtimeStore: EditorRuntimeStore) {
        self.runtimeStore = runtimeStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = EditorPaneRootAppKitView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.distribution = .fill
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        configureSeparator(tabSeparator)
        configureSeparator(findSeparator)
        configureSeparator(editorStatusSeparator)
        configureFindBarCallbacks()

        bodyContainerView.translatesAutoresizingMaskIntoConstraints = false

        editorContainerView.translatesAutoresizingMaskIntoConstraints = false
        terminalPanelView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(rootStack)
        rootStack.addArrangedSubview(splitView)
        rootStack.addArrangedSubview(editorStatusSeparator)
        rootStack.addArrangedSubview(editorStatusBarView)

        splitView.addArrangedSubview(editorContainerView)
        splitView.addArrangedSubview(terminalPanelView)

        editorContainerView.addSubview(stackView)
        stackView.addArrangedSubview(tabBarView)
        stackView.addArrangedSubview(tabSeparator)
        stackView.addArrangedSubview(findBarView)
        stackView.addArrangedSubview(findSeparator)
        stackView.addArrangedSubview(bodyContainerView)

        findBarView.isHidden = true
        findSeparator.isHidden = true

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            splitView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: editorContainerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: editorContainerView.bottomAnchor),

            tabBarView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: EditorMetrics.tabBarHeight),

            tabSeparator.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1),

            findBarView.widthAnchor.constraint(equalTo: stackView.widthAnchor),

            findSeparator.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            findSeparator.heightAnchor.constraint(equalToConstant: 1),

            bodyContainerView.widthAnchor.constraint(equalTo: stackView.widthAnchor),

            editorStatusSeparator.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            editorStatusSeparator.heightAnchor.constraint(equalToConstant: 1),

            editorStatusBarView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            editorStatusBarView.heightAnchor.constraint(equalToConstant: EditorMetrics.statusBarHeight)
        ])

        view = rootView
        showEmptyEditor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        activeRuntime?.updateLayout()
        applyTerminalSplitIfNeeded()
    }

    func update(
        workspaceID: ProjectWorkspaceSnapshot.ID?,
        editorMode: EditorMode,
        reviewDiffState: ReviewDiffState,
        reviewDiffBase: GitReviewDiffBase?,
        reviewDiffRemoteBranches: [GitRemoteBranchInfo],
        isLoadingReviewDiffRemoteBranches: Bool,
        reviewDiffRemoteBranchErrorMessage: String?,
        reviewDiffHideWhitespace: Bool,
        reviewDiffDisplayMode: Binding<ReviewDiffDisplayMode>,
        reviewDiffWrapLines: Binding<Bool>,
        tabs: [EditorTabSnapshot],
        selectedTabID: EditorTab.ID?,
        findPresentationRequest: EditorFindPresentationRequest?,
        implementationJumpRequest: EditorImplementationJumpRequest?,
        symbolIndexStatus: SymbolIndexStatusState,
        fileSearchIndexStatus: ProjectFileSearchIndexStatusState,
        gitRepositoryStatus: GitRepositoryStatus,
        gitSnapshot: GitRepositorySnapshot?,
        githubAuthStatus: GitHubAuthStatusState,
        githubPullRequestStatus: GitHubPullRequestStatus?,
        tabInputSetting: EditorTabInputSetting,
        lineWrappingMode: EditorLineWrappingMode,
        editorSession: @escaping (EditorTab.ID) -> EditorDocumentSession?,
        updateText: @escaping (String, EditorTab.ID) -> Void,
        updateSelection: @escaping (NSRange, EditorTab.ID) -> Void,
        updateScrollOrigin: @escaping (CGPoint, EditorTab.ID) -> Void,
        requestImplementationJump: @escaping (EditorTab.ID, Int) -> Void,
        implementationHoverRange: @escaping (EditorTab.ID, Int) async -> NSRange?,
        requestReviewDiffCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        reviewDiffCodeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?,
        selectTab: @escaping (EditorTab.ID) -> Void,
        setTabInputSetting: @escaping (EditorTabInputSetting) -> Void,
        switchGitBranch: @escaping (String) -> Void,
        refreshGitHubAuthStatus: @escaping () -> Void,
        logInToGitHub: @escaping () -> Void,
        openGitHubPullRequest: @escaping (URL) -> Void,
        selectReviewDiffBase: @escaping (GitReviewDiffBase) -> Void,
        loadReviewDiffRemoteBranches: @escaping (Bool) -> Void,
        refreshReviewDiff: @escaping () -> Void,
        setReviewDiffHideWhitespace: @escaping (Bool) -> Void,
        openReviewDiffFile: @escaping (URL) -> Void,
        closeTab: @escaping (EditorTab.ID) -> Void,
        moveTab: @escaping (EditorTab.ID, EditorTab.ID) -> Void,
        terminalWorkspaceURL: URL?,
        terminalTabs: [TerminalTabSnapshot],
        selectedTerminalTabID: TerminalTab.ID?,
        terminalFocusRequest: TerminalFocusRequest?,
        isTerminalMinimized: Bool,
        terminalView: @escaping (TerminalTab.ID) -> NSView?,
        createTerminalTab: @escaping () -> Void,
        selectTerminalTab: @escaping (TerminalTab.ID) -> Void,
        closeTerminalTab: @escaping (TerminalTab.ID) -> Void,
        toggleTerminalMinimized: @escaping () -> Void
    ) {
        let didChangeTerminalMinimized = self.isTerminalMinimized != isTerminalMinimized
        let didChangeSelectedTab = self.selectedTabID != selectedTabID

        self.workspaceID = workspaceID
        self.editorMode = editorMode
        self.reviewDiffState = reviewDiffState
        self.reviewDiffBase = reviewDiffBase
        self.reviewDiffRemoteBranches = reviewDiffRemoteBranches
        self.isLoadingReviewDiffRemoteBranches = isLoadingReviewDiffRemoteBranches
        self.reviewDiffRemoteBranchErrorMessage = reviewDiffRemoteBranchErrorMessage
        self.reviewDiffHideWhitespace = reviewDiffHideWhitespace
        self.reviewDiffDisplayMode = reviewDiffDisplayMode
        self.reviewDiffWrapLines = reviewDiffWrapLines
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.symbolIndexStatus = symbolIndexStatus
        self.fileSearchIndexStatus = fileSearchIndexStatus
        self.gitRepositoryStatus = gitRepositoryStatus
        self.gitSnapshot = gitSnapshot
        self.githubAuthStatus = githubAuthStatus
        self.githubPullRequestStatus = githubPullRequestStatus
        self.tabInputSetting = tabInputSetting
        self.lineWrappingMode = lineWrappingMode
        self.isTerminalMinimized = isTerminalMinimized
        self.terminalStatus = TerminalStatusBarState(
            tabCount: terminalTabs.count,
            isMinimized: isTerminalMinimized,
            isEnabled: terminalWorkspaceURL != nil
        )
        self.editorSession = editorSession
        self.updateText = updateText
        self.updateSelection = updateSelection
        self.updateScrollOrigin = updateScrollOrigin
        self.requestImplementationJump = requestImplementationJump
        self.implementationHoverRange = implementationHoverRange
        self.selectTab = selectTab
        self.setTabInputSetting = setTabInputSetting
        self.switchGitBranch = switchGitBranch
        self.refreshGitHubAuthStatus = refreshGitHubAuthStatus
        self.logInToGitHub = logInToGitHub
        self.openGitHubPullRequest = openGitHubPullRequest
        self.selectReviewDiffBase = selectReviewDiffBase
        self.loadReviewDiffRemoteBranches = loadReviewDiffRemoteBranches
        self.refreshReviewDiff = refreshReviewDiff
        self.setReviewDiffHideWhitespace = setReviewDiffHideWhitespace
        self.openReviewDiffFile = openReviewDiffFile
        self.closeTab = closeTab
        self.moveTab = moveTab
        self.toggleTerminalMinimized = toggleTerminalMinimized

        setTerminalPanelVisible(!isTerminalMinimized)
        updateTabBar()
        updateTerminalPanel(
            workspaceURL: terminalWorkspaceURL,
            tabs: terminalTabs,
            selectedTabID: selectedTerminalTabID,
            terminalFocusRequest: terminalFocusRequest,
            terminalView: terminalView,
            createTab: createTerminalTab,
            selectTab: selectTerminalTab,
            closeTab: closeTerminalTab
        )

        if didChangeTerminalMinimized {
            shouldApplyTerminalSplit = !isTerminalMinimized
        }

        if editorMode == .review {
            updateStatusBar(for: nil)
            updateFindBar(for: nil)
            setEditorChromeVisibility(hasOpenTab: false)
            showReviewDiff(
                state: reviewDiffState,
                selectedBase: reviewDiffBase,
                localBranches: gitSnapshot?.localBranches ?? [],
                remoteBranches: reviewDiffRemoteBranches,
                isLoadingRemoteBranches: isLoadingReviewDiffRemoteBranches,
                remoteBranchErrorMessage: reviewDiffRemoteBranchErrorMessage,
                hideWhitespace: reviewDiffHideWhitespace,
                displayMode: reviewDiffDisplayMode,
                wrapLines: reviewDiffWrapLines,
                selectBase: selectReviewDiffBase,
                loadRemoteBranches: loadReviewDiffRemoteBranches,
                refresh: refreshReviewDiff,
                setHideWhitespace: setReviewDiffHideWhitespace,
                openFile: openReviewDiffFile,
                requestCodeNavigation: requestReviewDiffCodeNavigation,
                codeNavigationHoverRange: reviewDiffCodeNavigationHoverRange
            )
            return
        }

        discardReviewDiffHostingView()

        guard let workspaceID,
              let selectedTabID,
              let selectedTab = tabs.first(where: { $0.id == selectedTabID }),
              let session = editorSession(selectedTabID) else {
            updateStatusBar(for: nil)
            updateFindBar(for: nil)
            setEditorChromeVisibility(hasOpenTab: false)
            showEmptyEditor()
            return
        }

        setEditorChromeVisibility(hasOpenTab: true)

        let runtime = runtimeStore.runtime(
            workspaceID: workspaceID,
            tab: selectedTab,
            session: session
        )
        runtime.delegate = self
        runtime.syncExternalTextIfNeeded(selectedTab.text)
        runtime.updateDiffDecorations(gitSnapshot?.diff(for: selectedTab.url)?.editorDecorations ?? [])
        runtime.updateTabInputSetting(tabInputSetting)
        runtime.updateLineWrappingMode(lineWrappingMode)
        showRuntime(
            runtime,
            activationFocusBehavior: runtimeStore.activationFocusBehavior(
                for: selectedTab,
                didChangeSelectedTab: didChangeSelectedTab
            )
        )
        runtime.applyPendingSelectionRevealIfNeeded()
        updateStatusBar(for: runtime)
        consumeFindPresentationRequestIfNeeded(findPresentationRequest)
        consumeImplementationJumpRequestIfNeeded(implementationJumpRequest)
        updateFindBar(for: runtime)
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        EditorMetrics.editorMinimumHeight
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard !isTerminalMinimized,
              terminalPanelView.superview === splitView else {
            return proposedMaximumPosition
        }

        return splitView.bounds.height - splitView.dividerThickness - EditorMetrics.terminalMinimumHeight
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !shouldApplyTerminalSplit,
              !isApplyingTerminalSplit,
              !isTerminalMinimized,
              terminalPanelView.superview === splitView else {
            return
        }

        let terminalHeight = terminalPanelView.frame.height
        if terminalHeight >= EditorMetrics.terminalMinimumHeight {
            lastTerminalHeight = terminalHeight
        }
    }

    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeText text: String) {
        guard let tabID = tabID(for: runtime) else { return }
        updateText?(text, tabID)
    }

    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeSelection selectedRange: NSRange) {
        guard let tabID = tabID(for: runtime) else { return }
        updateSelection?(selectedRange, tabID)
        updateStatusBar(for: runtime)
    }

    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeScrollOrigin scrollOrigin: CGPoint) {
        guard let tabID = tabID(for: runtime) else { return }
        updateScrollOrigin?(scrollOrigin, tabID)
    }

    func editorDocumentRuntime(_ runtime: EditorDocumentRuntime, didChangeFindState findState: EditorFindState) {
        guard activeRuntime === runtime else { return }
        updateFindBar(for: runtime)
    }

    func editorDocumentRuntimeDidRequestFindFocus(_ runtime: EditorDocumentRuntime) {
        guard activeRuntime === runtime else { return }
        updateFindBar(for: runtime)

        DispatchQueue.main.async { [weak self] in
            self?.findBarView.focusSearchField(selectText: true)
        }
    }

    func editorDocumentRuntime(
        _ runtime: EditorDocumentRuntime,
        didRequestImplementationJumpAt utf16Offset: Int
    ) {
        guard activeRuntime === runtime,
              let tabID = tabID(for: runtime) else {
            return
        }

        requestImplementationJump?(tabID, utf16Offset)
    }

    func editorDocumentRuntime(
        _ runtime: EditorDocumentRuntime,
        implementationHoverRangeAt utf16Offset: Int
    ) async -> NSRange? {
        guard activeRuntime === runtime,
              let tabID = tabID(for: runtime) else {
            return nil
        }

        return await implementationHoverRange?(tabID, utf16Offset)
    }

    private func configureFindBarCallbacks() {
        findBarView.onQueryChanged = { [weak self] query in
            self?.activeRuntime?.updateFindQuery(query)
        }
        findBarView.onReplacementChanged = { [weak self] replacement in
            self?.activeRuntime?.updateFindReplacement(replacement)
        }
        findBarView.onRegexChanged = { [weak self] isRegex in
            self?.activeRuntime?.setFindUsesRegularExpression(isRegex)
        }
        findBarView.onCaseSensitiveChanged = { [weak self] isCaseSensitive in
            self?.activeRuntime?.setFindCaseSensitive(isCaseSensitive)
        }
        findBarView.onToggleReplace = { [weak self] in
            guard let runtime = self?.activeRuntime else { return }
            runtime.setFindReplaceVisible(!runtime.findState.showsReplace)
        }
        findBarView.onPrevious = { [weak self] in
            self?.activeRuntime?.selectPreviousFindMatch()
        }
        findBarView.onNext = { [weak self] in
            self?.activeRuntime?.selectNextFindMatch()
        }
        findBarView.onReplace = { [weak self] in
            self?.activeRuntime?.replaceSelectedFindMatch()
        }
        findBarView.onReplaceAll = { [weak self] in
            self?.activeRuntime?.replaceAllFindMatches()
        }
        findBarView.onClose = { [weak self] in
            self?.activeRuntime?.dismissFind()
        }
    }

    private func consumeFindPresentationRequestIfNeeded(_ request: EditorFindPresentationRequest?) {
        guard let request,
              request.id != consumedFindPresentationRequestID,
              let activeRuntime else {
            return
        }

        consumedFindPresentationRequestID = request.id
        activeRuntime.presentFind(showsReplace: request.showsReplace)
        updateFindBar(for: activeRuntime)

        DispatchQueue.main.async { [weak self] in
            self?.findBarView.focusSearchField(selectText: true)
        }
    }

    private func consumeImplementationJumpRequestIfNeeded(_ request: EditorImplementationJumpRequest?) {
        guard let request,
              request.id != consumedImplementationJumpRequestID,
              let activeRuntime else {
            return
        }

        consumedImplementationJumpRequestID = request.id
        activeRuntime.requestImplementationJumpAtCurrentSelection()
    }

    private func updateFindBar(for runtime: EditorDocumentRuntime?) {
        guard let runtime,
              runtime.findState.isPresented else {
            findBarView.isHidden = true
            findSeparator.isHidden = true
            return
        }

        findBarView.isHidden = false
        findSeparator.isHidden = false
        findBarView.update(findState: runtime.findState)
    }

    private func updateTabBar() {
        tabBarView.update(
            tabs: tabs,
            selectedTabID: selectedTabID,
            selectTab: { [weak self] tabID in
                if let tab = self?.tabs.first(where: { $0.id == tabID }) {
                    self?.runtimeStore.requestActivationFocusBehavior(.focusTextView, for: tab.url)
                }

                self?.selectTab?(tabID)
            },
            closeTab: { [weak self] tabID in
                self?.closeTab?(tabID)
            },
            moveTab: { [weak self] movingID, targetID in
                self?.moveTab?(movingID, targetID)
            }
        )
    }

    private func updateTerminalPanel(
        workspaceURL: URL?,
        tabs: [TerminalTabSnapshot],
        selectedTabID: TerminalTab.ID?,
        terminalFocusRequest: TerminalFocusRequest?,
        terminalView: (TerminalTab.ID) -> NSView?,
        createTab: @escaping () -> Void,
        selectTab: @escaping (TerminalTab.ID) -> Void,
        closeTab: @escaping (TerminalTab.ID) -> Void
    ) {
        let selectedTerminalView = selectedTabID.flatMap(terminalView)

        terminalPanelView.update(
            workspaceURL: workspaceURL,
            tabs: tabs,
            selectedTabID: selectedTabID,
            selectedTerminalView: selectedTerminalView,
            createTab: createTab,
            selectTab: selectTab,
            closeTab: closeTab
        )

        consumeTerminalFocusRequestIfNeeded(
            terminalFocusRequest,
            selectedTabID: selectedTabID,
            selectedTerminalView: selectedTerminalView
        )
    }

    private func consumeTerminalFocusRequestIfNeeded(
        _ request: TerminalFocusRequest?,
        selectedTabID: TerminalTab.ID?,
        selectedTerminalView: NSView?
    ) {
        guard let request,
              request.id != consumedTerminalFocusRequestID,
              request.tabID == selectedTabID,
              let selectedTerminalView else {
            return
        }

        consumedTerminalFocusRequestID = request.id
        DispatchQueue.main.async { [weak selectedTerminalView] in
            guard let selectedTerminalView,
                  let window = selectedTerminalView.window else {
                return
            }

            window.makeFirstResponder(selectedTerminalView)
        }
    }

    private func showRuntime(
        _ runtime: EditorDocumentRuntime,
        activationFocusBehavior: EditorActivationFocusBehavior
    ) {
        var shouldActivateRuntime = false
        let shouldFocusRuntime = shouldFocusRuntime(for: activationFocusBehavior)

        if activeRuntime !== runtime {
            activeRuntime?.prepareForHide()
            activeRuntime?.delegate = nil
            replaceBodyContent(with: runtime.scrollView)
            activeRuntime = runtime
            shouldActivateRuntime = true
        } else if runtime.scrollView.superview !== bodyContainerView {
            replaceBodyContent(with: runtime.scrollView)
            shouldActivateRuntime = true
        }

        runtime.updateLayout()
        if shouldActivateRuntime {
            runtime.activate(focusesTextView: shouldFocusRuntime)
        }
    }

    private func discardReviewDiffHostingView() {
        reviewDiffHostingView?.removeFromSuperview()
        reviewDiffHostingView = nil
    }

    private func shouldFocusRuntime(for behavior: EditorActivationFocusBehavior) -> Bool {
        switch behavior {
        case .preserveIfTextViewFocused:
            activeRuntime?.isTextViewFirstResponder == true
        case .focusTextView:
            true
        case .keepCurrentFocus:
            false
        }
    }

    private func showReviewDiff(
        state: ReviewDiffState,
        selectedBase: GitReviewDiffBase?,
        localBranches: [GitLocalBranchInfo],
        remoteBranches: [GitRemoteBranchInfo],
        isLoadingRemoteBranches: Bool,
        remoteBranchErrorMessage: String?,
        hideWhitespace: Bool,
        displayMode: Binding<ReviewDiffDisplayMode>,
        wrapLines: Binding<Bool>,
        selectBase: ((GitReviewDiffBase) -> Void)?,
        loadRemoteBranches: ((Bool) -> Void)?,
        refresh: @escaping () -> Void,
        setHideWhitespace: ((Bool) -> Void)?,
        openFile: ((URL) -> Void)?,
        requestCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        codeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?
    ) {
        if activeRuntime != nil {
            activeRuntime?.prepareForHide()
            activeRuntime?.delegate = nil
            activeRuntime = nil
        }

        let rootView = ReviewDiffView(
            state: state,
            selectedBase: selectedBase,
            localBranches: localBranches,
            remoteBranches: remoteBranches,
            isLoadingRemoteBranches: isLoadingRemoteBranches,
            remoteBranchErrorMessage: remoteBranchErrorMessage,
            hideWhitespace: hideWhitespace,
            displayMode: displayMode,
            wrapLines: wrapLines,
            selectBase: { selectBase?($0) },
            loadRemoteBranches: { loadRemoteBranches?($0) },
            refresh: refresh,
            setHideWhitespace: { setHideWhitespace?($0) },
            openFile: { openFile?($0) },
            requestCodeNavigation: requestCodeNavigation,
            codeNavigationHoverRange: codeNavigationHoverRange
        )

        if let reviewDiffHostingView {
            reviewDiffHostingView.rootView = rootView
            if reviewDiffHostingView.superview !== bodyContainerView {
                replaceBodyContent(with: reviewDiffHostingView)
            }
            return
        }

        let hostingView = NSHostingView(rootView: rootView)
        reviewDiffHostingView = hostingView
        replaceBodyContent(with: hostingView)
    }

    private func showEmptyEditor() {
        if activeRuntime != nil {
            activeRuntime?.prepareForHide()
            activeRuntime?.delegate = nil
            activeRuntime = nil
        }

        updateStatusBar(for: nil)

        if emptyView.superview !== bodyContainerView {
            replaceBodyContent(with: emptyView)
        }
    }

    private func replaceBodyContent(with contentView: NSView) {
        bodyContainerView.subviews.forEach { $0.removeFromSuperview() }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainerView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: bodyContainerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: bodyContainerView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: bodyContainerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bodyContainerView.bottomAnchor)
        ])
    }

    private func setEditorChromeVisibility(hasOpenTab: Bool) {
        tabBarView.isHidden = !hasOpenTab
        tabSeparator.isHidden = !hasOpenTab
        editorStatusSeparator.isHidden = false
        editorStatusBarView.isHidden = false
    }

    private func updateStatusBar(for runtime: EditorDocumentRuntime?) {
        guard let runtime else {
            editorStatusBarView.update(
                position: nil,
                languageState: nil,
                tabInputSetting: nil,
                symbolIndexStatus: symbolIndexStatus,
                fileSearchIndexStatus: fileSearchIndexStatus,
                gitStatus: GitStatusBarState(status: gitRepositoryStatus),
                githubStatus: GitHubStatusBarState(status: githubAuthStatus),
                githubPullRequestStatus: GitHubPullRequestStatusBarState(status: githubPullRequestStatus),
                terminalStatus: terminalStatus,
                selectLanguage: { _ in },
                selectTabInputSetting: { _ in },
                switchGitBranch: { [weak self] branchName in
                    self?.switchGitBranch?(branchName)
                },
                refreshGitHubAuthStatus: { [weak self] in
                    self?.refreshGitHubAuthStatus?()
                },
                logInToGitHub: { [weak self] in
                    self?.logInToGitHub?()
                },
                openGitHubPullRequest: { [weak self] url in
                    self?.openGitHubPullRequest?(url)
                },
                toggleTerminal: { [weak self] in
                    self?.toggleTerminalMinimized?()
                }
            )
            return
        }

        editorStatusBarView.update(
            position: runtime.cursorPosition,
            languageState: runtime.syntaxLanguageState,
            tabInputSetting: tabInputSetting,
            symbolIndexStatus: symbolIndexStatus,
            fileSearchIndexStatus: fileSearchIndexStatus,
            gitStatus: GitStatusBarState(status: gitRepositoryStatus),
            githubStatus: GitHubStatusBarState(status: githubAuthStatus),
            githubPullRequestStatus: GitHubPullRequestStatusBarState(status: githubPullRequestStatus),
            terminalStatus: terminalStatus,
            selectLanguage: { [weak self, weak runtime] languageName in
                guard let self,
                      let runtime,
                      self.activeRuntime === runtime else {
                    return
                }

                runtime.setSyntaxLanguageOverride(languageName)
                self.updateStatusBar(for: runtime)
            },
            selectTabInputSetting: { [weak self, weak runtime] setting in
                guard let self,
                      let runtime,
                      self.activeRuntime === runtime else {
                    return
                }

                self.tabInputSetting = setting
                runtime.updateTabInputSetting(setting)
                self.setTabInputSetting?(setting)
                self.updateStatusBar(for: runtime)
            },
            switchGitBranch: { [weak self] branchName in
                self?.switchGitBranch?(branchName)
            },
            refreshGitHubAuthStatus: { [weak self] in
                self?.refreshGitHubAuthStatus?()
            },
            logInToGitHub: { [weak self] in
                self?.logInToGitHub?()
            },
            openGitHubPullRequest: { [weak self] url in
                self?.openGitHubPullRequest?(url)
            },
            toggleTerminal: { [weak self] in
                self?.toggleTerminalMinimized?()
            }
        )
    }

    private func tabID(for runtime: EditorDocumentRuntime) -> EditorTab.ID? {
        guard runtime.workspaceID == workspaceID else { return nil }
        return tabs.first { $0.documentID == runtime.documentID }?.id
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setTerminalPanelVisible(_ isVisible: Bool) {
        if isVisible {
            guard terminalPanelView.superview !== splitView else { return }
            splitView.addArrangedSubview(terminalPanelView)
            terminalPanelView.isHidden = false
            shouldApplyTerminalSplit = true
            view.needsLayout = true
            return
        }

        guard terminalPanelView.superview === splitView else { return }

        let terminalHeight = terminalPanelView.frame.height
        if terminalHeight >= EditorMetrics.terminalMinimumHeight {
            lastTerminalHeight = terminalHeight
        }

        splitView.removeArrangedSubview(terminalPanelView)
        terminalPanelView.removeFromSuperview()
        view.needsLayout = true
    }

    private func applyTerminalSplitIfNeeded() {
        guard shouldApplyTerminalSplit,
              !isTerminalMinimized,
              splitView.bounds.height > 0,
              splitView.subviews.count == 2,
              terminalPanelView.superview === splitView else {
            return
        }

        shouldApplyTerminalSplit = false

        let availableHeight = splitView.bounds.height - splitView.dividerThickness
        guard availableHeight > EditorMetrics.editorMinimumHeight else { return }

        let desiredTerminalHeight = lastTerminalHeight ?? availableHeight * EditorMetrics.terminalDefaultHeightRatio
        let maximumTerminalHeight = max(0, availableHeight - EditorMetrics.editorMinimumHeight)
        guard maximumTerminalHeight > 0 else { return }

        let terminalHeight = min(
            max(desiredTerminalHeight, EditorMetrics.terminalMinimumHeight),
            maximumTerminalHeight
        )
        let dividerPosition = availableHeight - terminalHeight

        isApplyingTerminalSplit = true
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
        isApplyingTerminalSplit = false
    }
}

private final class EditorPaneRootAppKitView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct TerminalStatusBarState: Equatable {
    let tabCount: Int
    let isMinimized: Bool
    let isEnabled: Bool

    var title: String {
        "Terminal \(tabCount)"
    }

    var toolTip: String {
        guard isEnabled else {
            return "Open a folder to use the terminal."
        }

        let action = isMinimized ? "Show" : "Hide"
        return "\(action) Terminal (\(tabCount) open)"
    }
}

private struct GitStatusBarState: Equatable {
    let title: String?
    let toolTip: String?
    let accessibilityValue: String
    let branches: [GitStatusBarBranchState]
    let canSwitchBranch: Bool

    init(status: GitRepositoryStatus) {
        switch status {
        case .inactive:
            title = nil
            toolTip = nil
            accessibilityValue = ""
            branches = []
            canSwitchBranch = false

        case .checking:
            title = "Git"
            toolTip = "Checking Git repository status."
            accessibilityValue = "Checking Git repository status"
            branches = []
            canSwitchBranch = false

        case .notRepository(let url):
            title = "No Git"
            toolTip = "\(url.lastPathComponent) is not in a Git repository."
            accessibilityValue = "Not a Git repository"
            branches = []
            canSwitchBranch = false

        case .repository(let snapshot):
            if snapshot.isRuriStyleWorktree {
                title = "\(snapshot.branch.displayName) (worktree)"
                toolTip = "\(snapshot.branch.detail)\nruri-style worktree: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                accessibilityValue = "\(snapshot.branch.displayName), ruri-style worktree"
                branches = snapshot.localBranches.map { branch in
                    GitStatusBarBranchState(
                        name: branch.name,
                        isCurrent: branch.name == snapshot.branch.displayName,
                        checkedOutWorktreeURL: branch.checkedOutWorktreeURL,
                        currentWorktreeURL: snapshot.worktreeRootURL
                    )
                }
                canSwitchBranch = true
            } else {
                branches = []
                canSwitchBranch = false

                switch snapshot.worktreeKind {
                case .main:
                    if snapshot.hasOtherWorktrees {
                        title = "\(snapshot.branch.displayName) Worktree Root"
                        toolTip = "\(snapshot.branch.detail)\nWorktree root: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                        accessibilityValue = "\(snapshot.branch.displayName), worktree root"
                    } else {
                        title = snapshot.branch.displayName
                        toolTip = snapshot.branch.detail
                        accessibilityValue = snapshot.branch.displayName
                    }

                case .linked:
                    title = "\(snapshot.branch.displayName) Worktree"
                    toolTip = "\(snapshot.branch.detail)\nLinked worktree: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                    accessibilityValue = "\(snapshot.branch.displayName), linked worktree"
                }
            }
        }
    }
}

private enum GitHubStatusBarAction: Equatable {
    case logIn
    case refresh
}

private enum GitHubStatusBarTint: Equatable {
    case primary
    case secondary
    case tertiary
    case red
}

private struct GitHubStatusBarState: Equatable {
    let title: String
    let toolTip: String
    let accessibilityValue: String
    let action: GitHubStatusBarAction?
    let tint: GitHubStatusBarTint

    init(status: GitHubAuthStatusState) {
        switch status {
        case .checking:
            title = "GitHub"
            toolTip = "Checking GitHub authentication."
            accessibilityValue = "Checking GitHub authentication"
            action = nil
            tint = .secondary

        case .authenticating:
            title = "GitHub"
            toolTip = "Starting GitHub login."
            accessibilityValue = "Starting GitHub login"
            action = nil
            tint = .secondary

        case .authenticated(let username):
            title = "@\(username)"
            toolTip = "Logged in to GitHub as \(username)."
            accessibilityValue = "Logged in to GitHub as \(username)"
            action = nil
            tint = .primary

        case .unauthenticated:
            title = "GitHub Login"
            toolTip = "Log in to GitHub with GitHub CLI."
            accessibilityValue = "Not logged in to GitHub"
            action = .logIn
            tint = .secondary

        case .unavailable(let message):
            title = "No gh"
            toolTip = message
            accessibilityValue = message
            action = nil
            tint = .tertiary

        case .failed(let message):
            title = "GitHub Error"
            toolTip = "\(message)\nClick to retry."
            accessibilityValue = "GitHub authentication failed"
            action = .refresh
            tint = .red
        }
    }
}

private struct GitHubPullRequestStatusBarState: Equatable {
    let title: String
    let toolTip: String
    let accessibilityValue: String
    let url: URL

    init?(status: GitHubPullRequestStatus?) {
        guard let status else { return nil }

        switch status {
        case .pullRequest(let pullRequest):
            title = pullRequest.isDraft ? "\(pullRequest.displayTitle) Draft" : pullRequest.displayTitle
            toolTip = "View pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)\n\(pullRequest.url.absoluteString)"
            accessibilityValue = "Pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)"
            url = pullRequest.url

        case .create(let creationLink):
            title = "Create PR"
            toolTip = "Create pull request \(creationLink.headBranch) into \(creationLink.baseBranch)\n\(creationLink.url.absoluteString)"
            accessibilityValue = "Create pull request"
            url = creationLink.url
        }
    }
}

private struct GitStatusBarBranchState: Equatable {
    let name: String
    let isCurrent: Bool
    let checkedOutWorktreeURL: URL?
    let currentWorktreeURL: URL

    var isCheckedOutInOtherWorktree: Bool {
        guard let checkedOutWorktreeURL else { return false }
        return !FileURLRewriter.urlsMatch(checkedOutWorktreeURL, currentWorktreeURL)
    }

    var isSelectable: Bool {
        !isCheckedOutInOtherWorktree
    }

    var toolTip: String {
        if isCurrent {
            return "Current branch"
        }

        if let checkedOutWorktreeURL,
           isCheckedOutInOtherWorktree {
            return "Already checked out at \(checkedOutWorktreeURL.path(percentEncoded: false))"
        }

        return "Switch to \(name)"
    }
}

private final class EditorBodyContainerAppKitView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class EditorFindBarAppKitView: NSView, NSSearchFieldDelegate, NSTextFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onReplacementChanged: ((String) -> Void)?
    var onRegexChanged: ((Bool) -> Void)?
    var onCaseSensitiveChanged: ((Bool) -> Void)?
    var onToggleReplace: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = NSSearchField()
    private let replacementField = NSTextField()
    private let matchLabel = NSTextField(labelWithString: "")
    private let replaceToggleButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private let caseButton = NSButton(checkboxWithTitle: "Case", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let closeButton = NSButton()
    private let replacementRow = NSStackView()

    private var isUpdating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(findState: EditorFindState) {
        isUpdating = true

        if searchField.stringValue != findState.query {
            searchField.stringValue = findState.query
        }
        if replacementField.stringValue != findState.replacement {
            replacementField.stringValue = findState.replacement
        }

        matchLabel.stringValue = findState.matchDescription
        matchLabel.textColor = findState.errorMessage == nil ? .secondaryLabelColor : .systemRed

        regexButton.state = findState.isRegex ? .on : .off
        caseButton.state = findState.isCaseSensitive ? .on : .off
        previousButton.isEnabled = findState.canNavigate
        nextButton.isEnabled = findState.canNavigate
        replaceButton.isEnabled = findState.canReplace
        replaceAllButton.isEnabled = findState.canReplaceAll
        replacementRow.isHidden = !findState.showsReplace
        replaceToggleButton.image = NSImage(
            systemSymbolName: findState.showsReplace ? "chevron.down" : "chevron.right",
            accessibilityDescription: findState.showsReplace ? "Hide Replace" : "Show Replace"
        )
        replaceToggleButton.toolTip = findState.showsReplace ? "Hide Replace" : "Show Replace"

        isUpdating = false
    }

    func focusSearchField(selectText: Bool) {
        if selectText {
            searchField.selectText(nil)
        } else {
            window?.makeFirstResponder(searchField)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isUpdating,
              let textField = notification.object as? NSTextField else {
            return
        }

        if textField === searchField {
            onQueryChanged?(textField.stringValue)
        } else if textField === replacementField {
            onReplacementChanged?(textField.stringValue)
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === searchField {
                onNext?()
            } else if control === replacementField {
                onReplace?()
            }
            return true

        default:
            return false
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .fill
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let searchRow = NSStackView()
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.distribution = .fill
        searchRow.spacing = 7
        searchRow.translatesAutoresizingMaskIntoConstraints = false

        replacementRow.orientation = .horizontal
        replacementRow.alignment = .centerY
        replacementRow.distribution = .fill
        replacementRow.spacing = 7
        replacementRow.translatesAutoresizingMaskIntoConstraints = false

        configureSearchField()
        configureReplacementField()
        configureMatchLabel()
        configureIconButton(
            replaceToggleButton,
            systemSymbolName: "chevron.right",
            accessibilityDescription: "Show Replace",
            action: #selector(toggleReplaceClicked)
        )
        configureIconButton(
            previousButton,
            systemSymbolName: "chevron.up",
            accessibilityDescription: "Previous Match",
            action: #selector(previousClicked)
        )
        configureIconButton(
            nextButton,
            systemSymbolName: "chevron.down",
            accessibilityDescription: "Next Match",
            action: #selector(nextClicked)
        )
        configureIconButton(
            closeButton,
            systemSymbolName: "xmark",
            accessibilityDescription: "Close Find",
            action: #selector(closeClicked)
        )
        configureToggle(regexButton, action: #selector(regexClicked))
        configureToggle(caseButton, action: #selector(caseClicked))
        configureActionButton(replaceButton, action: #selector(replaceClicked))
        configureActionButton(replaceAllButton, action: #selector(replaceAllClicked))

        let replacementIndent = NSView()
        replacementIndent.translatesAutoresizingMaskIntoConstraints = false
        replacementIndent.widthAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true

        addSubview(rootStack)
        rootStack.addArrangedSubview(searchRow)
        rootStack.addArrangedSubview(replacementRow)

        searchRow.addArrangedSubview(replaceToggleButton)
        searchRow.addArrangedSubview(searchField)
        searchRow.addArrangedSubview(matchLabel)
        searchRow.addArrangedSubview(previousButton)
        searchRow.addArrangedSubview(nextButton)
        searchRow.addArrangedSubview(regexButton)
        searchRow.addArrangedSubview(caseButton)
        searchRow.addArrangedSubview(closeButton)

        replacementRow.addArrangedSubview(replacementIndent)
        replacementRow.addArrangedSubview(replacementField)
        replacementRow.addArrangedSubview(replaceButton)
        replacementRow.addArrangedSubview(replaceAllButton)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            searchRow.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            searchRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            replacementRow.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            replacementRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            replacementField.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            replacementField.widthAnchor.constraint(equalTo: searchField.widthAnchor),
            matchLabel.widthAnchor.constraint(equalToConstant: 84)
        ])
    }

    private func configureSearchField() {
        searchField.placeholderString = "Find"
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.delegate = self
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureReplacementField() {
        replacementField.placeholderString = "Replace"
        replacementField.controlSize = .small
        replacementField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        replacementField.delegate = self
        replacementField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replacementField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureMatchLabel() {
        matchLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.alignment = .right
        matchLabel.lineBreakMode = .byTruncatingMiddle
        matchLabel.maximumNumberOfLines = 1
        matchLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureIconButton(
        _ button: NSButton,
        systemSymbolName: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        button.image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )
        button.toolTip = accessibilityDescription
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureToggle(_ button: NSButton, action: Selector) {
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureActionButton(_ button: NSButton, action: Selector) {
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc private func toggleReplaceClicked() {
        onToggleReplace?()
    }

    @objc private func previousClicked() {
        onPrevious?()
    }

    @objc private func nextClicked() {
        onNext?()
    }

    @objc private func regexClicked() {
        guard !isUpdating else { return }
        onRegexChanged?(regexButton.state == .on)
    }

    @objc private func caseClicked() {
        guard !isUpdating else { return }
        onCaseSensitiveChanged?(caseButton.state == .on)
    }

    @objc private func replaceClicked() {
        onReplace?()
    }

    @objc private func replaceAllClicked() {
        onReplaceAll?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

private final class EditorTabBarView: NSView {
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        tabs: [EditorTabSnapshot],
        selectedTabID: EditorTab.ID?,
        selectTab: @escaping (EditorTab.ID) -> Void,
        closeTab: @escaping (EditorTab.ID) -> Void,
        moveTab: @escaping (EditorTab.ID, EditorTab.ID) -> Void
    ) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for tab in tabs {
            let tabView = EditorTabItemAppKitView(
                tab: tab,
                isSelected: tab.id == selectedTabID,
                selectTab: selectTab,
                closeTab: closeTab,
                moveTab: moveTab
            )
            stackView.addArrangedSubview(tabView)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        contentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.documentView = contentView
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -6),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

private final class EditorTabItemAppKitView: NSView, NSDraggingSource {
    private static let tabPasteboardType = NSPasteboard.PasteboardType("engineering.ooo.ruri.editor-tab-id")

    private let tabID: EditorTab.ID
    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyIndicator = DirtyIndicatorAppKitView()
    private let closeButton = NSButton()
    private let isSelected: Bool
    private let selectTab: (EditorTab.ID) -> Void
    private let closeTab: (EditorTab.ID) -> Void
    private let moveTab: (EditorTab.ID, EditorTab.ID) -> Void

    private var mouseDownEvent: NSEvent?

    init(
        tab: EditorTabSnapshot,
        isSelected: Bool,
        selectTab: @escaping (EditorTab.ID) -> Void,
        closeTab: @escaping (EditorTab.ID) -> Void,
        moveTab: @escaping (EditorTab.ID, EditorTab.ID) -> Void
    ) {
        tabID = tab.id
        self.isSelected = isSelected
        self.selectTab = selectTab
        self.closeTab = closeTab
        self.moveTab = moveTab

        super.init(frame: .zero)

        setup(
            title: tab.url.lastPathComponent,
            hasUnsavedChanges: tab.hasUnsavedChanges,
            externalStatus: tab.externalStatus
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if containsEvent(event, in: closeButton) {
            mouseDownEvent = nil
            closeTab(tabID)
            return
        }

        mouseDownEvent = event
        selectTab(tabID)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent,
              !containsEvent(mouseDownEvent, in: closeButton) else {
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabID.uuidString, forType: Self.tabPasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: snapshotForDragging())

        beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
        self.mouseDownEvent = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTabID(from: sender) != nil else { return [] }
        return .move
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedTabID(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let movingID = draggedTabID(from: sender),
              movingID != tabID else {
            return false
        }

        moveTab(movingID, tabID)
        return true
    }

    @objc private func closeButtonClicked() {
        mouseDownEvent = nil
        closeTab(tabID)
    }

    private func setup(
        title: String,
        hasUnsavedChanges: Bool,
        externalStatus: OpenDocumentExternalStatus
    ) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
        toolTip = externalStatus.displayDescription

        registerForDraggedTypes([Self.tabPasteboardType])

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: EditorMetrics.tabHeight).isActive = true

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        dirtyIndicator.hasUnsavedChanges = hasUnsavedChanges
        dirtyIndicator.externalStatus = externalStatus
        dirtyIndicator.toolTip = externalStatus.displayDescription

        let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let titleColor = isSelected ? NSColor.labelColor : .secondaryLabelColor
        titleLabel.font = titleFont
        titleLabel.textColor = titleColor
        titleLabel.attributedStringValue = attributedTitle(
            title,
            font: titleFont,
            color: titleColor,
            externalStatus: externalStatus
        )
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        closeButton.sendAction(on: [.leftMouseDown])
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        stackView.addArrangedSubview(dirtyIndicator)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private func containsEvent(_ event: NSEvent, in view: NSView) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        let hitFrame = convert(view.bounds, from: view).insetBy(dx: -4, dy: -4)
        return hitFrame.contains(location)
    }

    private func draggedTabID(from sender: NSDraggingInfo) -> EditorTab.ID? {
        guard let uuidString = sender.draggingPasteboard.string(forType: Self.tabPasteboardType),
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }

        return uuid
    }

    private func attributedTitle(
        _ title: String,
        font: NSFont,
        color: NSColor,
        externalStatus: OpenDocumentExternalStatus
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        if externalStatus == .deleted {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = color
        }

        return NSAttributedString(string: title, attributes: attributes)
    }

    private func snapshotForDragging() -> NSImage {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }

        cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

private final class EditorStatusBarAppKitView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let terminalButton = NSButton()
    private let symbolButton = NSButton()
    private let fileSearchButton = NSButton()
    private let gitButton = NSButton()
    private let pullRequestButton = NSButton()
    private let githubButton = NSButton()
    private let positionLabel = NSTextField(labelWithString: "")
    private let tabInputButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: false)

    private var isUpdating = false
    private var languageState: EditorSyntaxLanguageState?
    private var tabInputSetting: EditorTabInputSetting?
    private var symbolIndexStatus: SymbolIndexStatusState?
    private var fileSearchIndexStatus: ProjectFileSearchIndexStatusState?
    private var gitStatus: GitStatusBarState?
    private var githubPullRequestStatus: GitHubPullRequestStatusBarState?
    private var githubStatus: GitHubStatusBarState?
    private var terminalStatus: TerminalStatusBarState?
    private var selectLanguage: ((String?) -> Void)?
    private var selectTabInputSetting: ((EditorTabInputSetting) -> Void)?
    private var switchGitBranch: ((String) -> Void)?
    private var refreshGitHubAuthStatus: (() -> Void)?
    private var logInToGitHub: (() -> Void)?
    private var openGitHubPullRequest: ((URL) -> Void)?
    private var toggleTerminal: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        position: EditorCursorPosition?,
        languageState: EditorSyntaxLanguageState?,
        tabInputSetting: EditorTabInputSetting?,
        symbolIndexStatus: SymbolIndexStatusState,
        fileSearchIndexStatus: ProjectFileSearchIndexStatusState,
        gitStatus: GitStatusBarState,
        githubStatus: GitHubStatusBarState,
        githubPullRequestStatus: GitHubPullRequestStatusBarState?,
        terminalStatus: TerminalStatusBarState,
        selectLanguage: @escaping (String?) -> Void,
        selectTabInputSetting: @escaping (EditorTabInputSetting) -> Void,
        switchGitBranch: @escaping (String) -> Void,
        refreshGitHubAuthStatus: @escaping () -> Void,
        logInToGitHub: @escaping () -> Void,
        openGitHubPullRequest: @escaping (URL) -> Void,
        toggleTerminal: @escaping () -> Void
    ) {
        positionLabel.stringValue = position?.displayText ?? ""
        self.selectLanguage = selectLanguage
        self.selectTabInputSetting = selectTabInputSetting
        self.switchGitBranch = switchGitBranch
        self.refreshGitHubAuthStatus = refreshGitHubAuthStatus
        self.logInToGitHub = logInToGitHub
        self.openGitHubPullRequest = openGitHubPullRequest
        self.toggleTerminal = toggleTerminal
        updateTerminalButton(terminalStatus)
        updateFileSearchButton(fileSearchIndexStatus)
        updateSymbolButton(symbolIndexStatus)
        updateGitButton(gitStatus)
        updatePullRequestButton(githubPullRequestStatus)
        updateGitHubButton(githubStatus)
        languageButton.isHidden = languageState == nil
        tabInputButton.isHidden = tabInputSetting == nil

        if self.languageState != languageState {
            self.languageState = languageState
            rebuildLanguageMenu()
        } else {
            selectCurrentLanguage()
        }

        if self.tabInputSetting != tabInputSetting {
            self.tabInputSetting = tabInputSetting
            rebuildTabInputMenu()
        } else {
            selectCurrentTabInputSetting()
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundView.material = .sidebar
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .followsWindowActiveState
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        positionLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .right
        positionLabel.lineBreakMode = .byTruncatingTail
        positionLabel.maximumNumberOfLines = 1
        positionLabel.setContentHuggingPriority(.required, for: .horizontal)

        terminalButton.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")
        terminalButton.imagePosition = .imageLeading
        terminalButton.imageScaling = .scaleProportionallyDown
        terminalButton.isBordered = false
        terminalButton.contentTintColor = .secondaryLabelColor
        terminalButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        terminalButton.controlSize = .small
        terminalButton.target = self
        terminalButton.action = #selector(terminalButtonClicked)
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        terminalButton.setContentHuggingPriority(.required, for: .horizontal)
        terminalButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        symbolButton.isBordered = false
        symbolButton.imagePosition = .imageLeading
        symbolButton.imageScaling = .scaleProportionallyDown
        symbolButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        symbolButton.controlSize = .small
        symbolButton.translatesAutoresizingMaskIntoConstraints = false
        symbolButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        symbolButton.setContentHuggingPriority(.required, for: .horizontal)
        symbolButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        fileSearchButton.isBordered = false
        fileSearchButton.imagePosition = .imageLeading
        fileSearchButton.imageScaling = .scaleProportionallyDown
        fileSearchButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fileSearchButton.controlSize = .small
        fileSearchButton.translatesAutoresizingMaskIntoConstraints = false
        fileSearchButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        fileSearchButton.setContentHuggingPriority(.required, for: .horizontal)
        fileSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        gitButton.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git Branch")
        gitButton.imagePosition = .imageLeading
        gitButton.imageScaling = .scaleProportionallyDown
        gitButton.isBordered = false
        gitButton.contentTintColor = .secondaryLabelColor
        gitButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        gitButton.controlSize = .small
        gitButton.cell?.lineBreakMode = .byTruncatingMiddle
        gitButton.target = self
        gitButton.action = #selector(gitButtonClicked)
        gitButton.translatesAutoresizingMaskIntoConstraints = false
        gitButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        gitButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        gitButton.setContentHuggingPriority(.required, for: .horizontal)
        gitButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        pullRequestButton.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "Pull Request")
        pullRequestButton.imagePosition = .imageLeading
        pullRequestButton.imageScaling = .scaleProportionallyDown
        pullRequestButton.title = ""
        pullRequestButton.toolTip = nil
        pullRequestButton.isHidden = true
        pullRequestButton.isEnabled = false
        pullRequestButton.isBordered = false
        pullRequestButton.contentTintColor = .secondaryLabelColor
        pullRequestButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pullRequestButton.controlSize = .small
        pullRequestButton.cell?.lineBreakMode = .byTruncatingTail
        pullRequestButton.target = self
        pullRequestButton.action = #selector(pullRequestButtonClicked)
        pullRequestButton.translatesAutoresizingMaskIntoConstraints = false
        pullRequestButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        pullRequestButton.setContentHuggingPriority(.required, for: .horizontal)
        pullRequestButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        githubButton.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "GitHub")
        githubButton.imagePosition = .imageLeading
        githubButton.imageScaling = .scaleProportionallyDown
        githubButton.isBordered = false
        githubButton.contentTintColor = .secondaryLabelColor
        githubButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        githubButton.controlSize = .small
        githubButton.cell?.lineBreakMode = .byTruncatingMiddle
        githubButton.target = self
        githubButton.action = #selector(githubButtonClicked)
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        githubButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize).isActive = true
        githubButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
        githubButton.setContentHuggingPriority(.required, for: .horizontal)
        githubButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        languageButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        languageButton.controlSize = .small
        languageButton.bezelStyle = .inline
        languageButton.isBordered = false
        languageButton.target = self
        languageButton.action = #selector(languageSelectionDidChange(_:))
        languageButton.setContentHuggingPriority(.required, for: .horizontal)

        tabInputButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tabInputButton.controlSize = .small
        tabInputButton.bezelStyle = .inline
        tabInputButton.isBordered = false
        tabInputButton.target = self
        tabInputButton.action = #selector(tabInputSelectionDidChange(_:))
        tabInputButton.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(backgroundView)
        addSubview(stackView)
        stackView.addArrangedSubview(terminalButton)
        stackView.addArrangedSubview(gitButton)
        stackView.addArrangedSubview(pullRequestButton)
        stackView.addArrangedSubview(githubButton)
        stackView.addArrangedSubview(fileSearchButton)
        stackView.addArrangedSubview(symbolButton)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(positionLabel)
        stackView.addArrangedSubview(tabInputButton)
        stackView.addArrangedSubview(languageButton)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateTerminalButton(_ terminalStatus: TerminalStatusBarState) {
        guard self.terminalStatus != terminalStatus else { return }

        self.terminalStatus = terminalStatus
        terminalButton.title = terminalStatus.title
        terminalButton.toolTip = terminalStatus.toolTip
        terminalButton.isEnabled = terminalStatus.isEnabled
        terminalButton.contentTintColor = terminalStatus.isMinimized ? .tertiaryLabelColor : .secondaryLabelColor
        terminalButton.setAccessibilityValue("\(terminalStatus.tabCount) open")
    }

    private func updateFileSearchButton(_ fileSearchIndexStatus: ProjectFileSearchIndexStatusState) {
        guard self.fileSearchIndexStatus != fileSearchIndexStatus else { return }

        self.fileSearchIndexStatus = fileSearchIndexStatus
        fileSearchButton.title = fileSearchIndexStatus.title
        fileSearchButton.toolTip = fileSearchIndexStatus.detail
        fileSearchButton.isEnabled = fileSearchIndexStatus != .inactive
        fileSearchButton.image = NSImage(
            systemSymbolName: fileSearchIndexStatus.systemImageName,
            accessibilityDescription: fileSearchIndexStatus.title
        )
        fileSearchButton.contentTintColor = color(for: fileSearchIndexStatus.severity)
        fileSearchButton.setAccessibilityValue(fileSearchIndexStatus.detail)
    }

    private func updateSymbolButton(_ symbolIndexStatus: SymbolIndexStatusState) {
        guard self.symbolIndexStatus != symbolIndexStatus else { return }

        self.symbolIndexStatus = symbolIndexStatus
        symbolButton.title = symbolIndexStatus.title
        symbolButton.toolTip = symbolIndexStatus.detail
        symbolButton.isEnabled = symbolIndexStatus != .inactive
        symbolButton.image = NSImage(
            systemSymbolName: symbolIndexStatus.systemImageName,
            accessibilityDescription: symbolIndexStatus.title
        )
        symbolButton.contentTintColor = color(for: symbolIndexStatus.severity)
        symbolButton.setAccessibilityValue(symbolIndexStatus.detail)
    }

    private func updateGitButton(_ gitStatus: GitStatusBarState) {
        guard self.gitStatus != gitStatus else { return }

        self.gitStatus = gitStatus
        guard let title = gitStatus.title,
              !title.isEmpty else {
            gitButton.title = ""
            gitButton.toolTip = nil
            gitButton.isHidden = true
            gitButton.isEnabled = false
            gitButton.setAccessibilityValue("")
            return
        }

        gitButton.isHidden = false
        gitButton.isEnabled = gitStatus.canSwitchBranch
        gitButton.title = title
        gitButton.toolTip = gitStatus.toolTip
        gitButton.setAccessibilityValue(gitStatus.accessibilityValue)
    }

    private func updatePullRequestButton(_ githubPullRequestStatus: GitHubPullRequestStatusBarState?) {
        guard self.githubPullRequestStatus != githubPullRequestStatus else { return }

        self.githubPullRequestStatus = githubPullRequestStatus
        guard let githubPullRequestStatus else {
            pullRequestButton.title = ""
            pullRequestButton.toolTip = nil
            pullRequestButton.isHidden = true
            pullRequestButton.isEnabled = false
            pullRequestButton.setAccessibilityValue("")
            return
        }

        pullRequestButton.isHidden = false
        pullRequestButton.isEnabled = true
        pullRequestButton.title = githubPullRequestStatus.title
        pullRequestButton.toolTip = githubPullRequestStatus.toolTip
        pullRequestButton.contentTintColor = .secondaryLabelColor
        pullRequestButton.setAccessibilityValue(githubPullRequestStatus.accessibilityValue)
    }

    private func updateGitHubButton(_ githubStatus: GitHubStatusBarState) {
        guard self.githubStatus != githubStatus else { return }

        self.githubStatus = githubStatus
        githubButton.title = githubStatus.title
        githubButton.toolTip = githubStatus.toolTip
        githubButton.isEnabled = githubStatus.action != nil
        githubButton.contentTintColor = color(for: githubStatus.tint)
        githubButton.setAccessibilityValue(githubStatus.accessibilityValue)
    }

    private func color(for severity: SymbolIndexStatusState.Severity) -> NSColor {
        switch severity {
        case .inactive:
            .tertiaryLabelColor
        case .info:
            .secondaryLabelColor
        case .ready:
            .systemGreen
        case .error:
            .systemRed
        }
    }

    private func color(for tint: GitHubStatusBarTint) -> NSColor {
        switch tint {
        case .primary:
            .labelColor
        case .secondary:
            .secondaryLabelColor
        case .tertiary:
            .tertiaryLabelColor
        case .red:
            .systemRed
        }
    }

    private func color(for severity: ProjectFileSearchIndexStatusState.Severity) -> NSColor {
        switch severity {
        case .inactive:
            .tertiaryLabelColor
        case .info:
            .secondaryLabelColor
        case .ready:
            .systemGreen
        case .error:
            .systemRed
        }
    }

    private func rebuildLanguageMenu() {
        isUpdating = true
        languageButton.removeAllItems()

        guard let languageState else {
            languageButton.isEnabled = false
            isUpdating = false
            return
        }

        languageButton.isEnabled = true
        languageButton.addItem(withTitle: languageState.autoDisplayName)
        languageButton.lastItem?.representedObject = nil

        if !languageState.languageOptions.isEmpty {
            languageButton.menu?.addItem(.separator())
        }

        for option in languageState.languageOptions {
            languageButton.addItem(withTitle: option.displayName)
            languageButton.lastItem?.representedObject = option.identifier
        }

        selectCurrentLanguage()
        isUpdating = false
    }

    private func selectCurrentLanguage() {
        guard let languageState else { return }

        isUpdating = true
        if let selectedLanguageName = languageState.selectedLanguageName,
           let item = languageButton.itemArray.first(where: { $0.representedObject as? String == selectedLanguageName }) {
            languageButton.select(item)
        } else if languageButton.numberOfItems > 0 {
            languageButton.selectItem(at: 0)
        }
        isUpdating = false
    }

    private func rebuildTabInputMenu() {
        isUpdating = true
        tabInputButton.removeAllItems()

        guard tabInputSetting != nil else {
            tabInputButton.isEnabled = false
            isUpdating = false
            return
        }

        tabInputButton.isEnabled = true
        for mode in EditorTabInputSetting.Mode.allCases {
            if tabInputButton.numberOfItems > 0 {
                tabInputButton.menu?.addItem(.separator())
            }

            for width in EditorTabInputSetting.allowedWidths {
                let setting = EditorTabInputSetting(mode: mode, width: width)
                tabInputButton.addItem(withTitle: setting.displayText)
                tabInputButton.lastItem?.representedObject = setting.identifier
            }
        }

        selectCurrentTabInputSetting()
        isUpdating = false
    }

    private func selectCurrentTabInputSetting() {
        guard let tabInputSetting else { return }

        isUpdating = true
        if let item = tabInputButton.itemArray.first(where: { $0.representedObject as? String == tabInputSetting.identifier }) {
            tabInputButton.select(item)
        } else if tabInputButton.numberOfItems > 0 {
            tabInputButton.selectItem(at: 0)
        }
        tabInputButton.toolTip = "Tab Input: \(tabInputSetting.displayText)"
        tabInputButton.setAccessibilityValue(tabInputSetting.displayText)
        isUpdating = false
    }

    @objc private func languageSelectionDidChange(_ sender: NSPopUpButton) {
        guard !isUpdating else { return }
        selectLanguage?(sender.selectedItem?.representedObject as? String)
    }

    @objc private func tabInputSelectionDidChange(_ sender: NSPopUpButton) {
        guard !isUpdating,
              let identifier = sender.selectedItem?.representedObject as? String,
              let setting = EditorTabInputSetting(identifier: identifier) else {
            return
        }

        selectTabInputSetting?(setting)
    }

    @objc private func gitButtonClicked() {
        guard let gitStatus,
              gitStatus.canSwitchBranch else {
            return
        }

        let menu = NSMenu()
        if gitStatus.branches.isEmpty {
            let item = NSMenuItem(title: "No local branches", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for branch in gitStatus.branches {
                let item = NSMenuItem(
                    title: branch.name,
                    action: #selector(gitBranchMenuItemClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = branch.name
                item.state = branch.isCurrent ? .on : .off
                item.isEnabled = branch.isSelectable
                item.toolTip = branch.toolTip
                menu.addItem(item)
            }
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: gitButton.bounds.height + 2),
            in: gitButton
        )
    }

    @objc private func githubButtonClicked() {
        guard let action = githubStatus?.action else { return }

        switch action {
        case .logIn:
            logInToGitHub?()
        case .refresh:
            refreshGitHubAuthStatus?()
        }
    }

    @objc private func pullRequestButtonClicked() {
        guard let url = githubPullRequestStatus?.url else { return }
        openGitHubPullRequest?(url)
    }

    @objc private func gitBranchMenuItemClicked(_ sender: NSMenuItem) {
        guard let branchName = sender.representedObject as? String else { return }
        switchGitBranch?(branchName)
    }

    @objc private func terminalButtonClicked() {
        toggleTerminal?()
    }
}

private final class DirtyIndicatorAppKitView: NSView {
    var hasUnsavedChanges = false {
        didSet {
            needsDisplay = true
        }
    }
    var externalStatus = OpenDocumentExternalStatus.normal {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 7).isActive = true
        heightAnchor.constraint(equalToConstant: 7).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let fillColor else { return }

        fillColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    private var fillColor: NSColor? {
        switch externalStatus {
        case .conflict, .deleted:
            .systemRed
        case .externallyModified:
            nil
        case .normal:
            hasUnsavedChanges ? .systemOrange : nil
        }
    }
}

private final class EditorEmptyAppKitView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "No File Selected")
    private let descriptionLabel = NSTextField(labelWithString: "左のファイルツリーからファイルを選択してください")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center

        descriptionLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center

        addSubview(stackView)
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            imageView.widthAnchor.constraint(equalToConstant: 56),
            imageView.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
}
