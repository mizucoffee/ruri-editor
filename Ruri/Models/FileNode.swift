//
//  FileNode.swift
//  ruri
//

import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var isExpanded: Bool
    var isLoadingChildren: Bool
    var isIgnored: Bool

    nonisolated init(
        url: URL,
        name: String,
        isDirectory: Bool,
        children: [FileNode]? = nil,
        isExpanded: Bool = false,
        isLoadingChildren: Bool = false,
        isIgnored: Bool = false
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
        self.isLoadingChildren = isLoadingChildren
        self.isIgnored = isIgnored
    }

    var id: URL {
        url
    }

    var systemImage: String {
        isDirectory ? "folder" : "doc.text"
    }
}
