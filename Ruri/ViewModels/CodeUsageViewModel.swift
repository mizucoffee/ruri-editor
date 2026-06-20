//
//  CodeUsageViewModel.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class CodeUsageViewModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var title = "Usages"
    @Published private(set) var results: [CodeUsageResult] = []
    @Published private(set) var selectedResultID: CodeUsageResult.ID?

    var selectedResult: CodeUsageResult? {
        guard let selectedResultID else { return results.first }
        return results.first { $0.id == selectedResultID } ?? results.first
    }

    var summaryDescription: String {
        let suffix = title == "Locations" ? "location" : "usage"
        return results.count == 1 ? "1 \(suffix)" : "\(results.count) \(suffix)s"
    }

    func present(results: [CodeUsageResult], title: String = "Usages") {
        self.title = title
        self.results = results
        isPresented = true
        repairSelection()
    }

    func dismiss() {
        isPresented = false
        title = "Usages"
        results = []
        selectedResultID = nil
    }

    func selectNextResult() {
        moveSelection(offset: 1)
    }

    func selectPreviousResult() {
        moveSelection(offset: -1)
    }

    private func repairSelection() {
        guard !results.isEmpty else {
            selectedResultID = nil
            return
        }

        if let selectedResultID,
           results.contains(where: { $0.id == selectedResultID }) {
            return
        }

        selectedResultID = results[0].id
    }

    private func moveSelection(offset: Int) {
        guard !results.isEmpty else { return }

        let currentIndex = selectedResult.flatMap { selectedResult in
            results.firstIndex { $0.id == selectedResult.id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)

        selectedResultID = results[nextIndex].id
    }
}
