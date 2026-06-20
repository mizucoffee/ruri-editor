//
//  FileRow.swift
//  ruri
//

import SwiftUI

struct FileRow: View {
    let node: FileNode
    let action: () -> Void

    var body: some View {
        if node.isDirectory {
            label
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        Label(node.name, systemImage: node.systemImage)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FileRow(
        node: FileNode(
            url: URL(filePath: "/tmp/TestFile.swift"),
            name: "TestFile.swift",
            isDirectory: false
        ),
        action: {}
    )
}
