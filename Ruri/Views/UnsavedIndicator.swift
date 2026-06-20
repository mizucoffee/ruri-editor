//
//  UnsavedIndicator.swift
//  ruri
//

import SwiftUI

struct UnsavedIndicator: View {
    let hasUnsavedChanges: Bool

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(hasUnsavedChanges ? .orange : .clear)
            .accessibilityLabel(hasUnsavedChanges ? "Unsaved changes" : "No unsaved changes")
    }
}
