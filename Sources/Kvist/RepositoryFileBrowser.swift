import AppKit
import SwiftUI

private struct RepositoryFileTreeRevision: Hashable {
    let repositoryPath: String?
    let automatic: Int
}

struct RepositoryFileBrowser: View {
    @EnvironmentObject private var model: RepositoryModel
    @State private var items: [RepositoryFileTreeItem] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            browserHeader

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            browserContents
        }
        .task(id: reloadRevision) {
            await loadRootItems()
        }
    }

    private var browserHeader: some View {
        HStack(spacing: 8) {
            RepositoryModePicker()

            Spacer()

            RepositoryTerminalButton()
        }
        // 22pt leading and 46pt height match ChangesActionBar so the mode
        // picker stays in the same place when switching workspace modes.
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .frame(height: 46)
    }

    @ViewBuilder
    private var browserContents: some View {
        if isLoading && items.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading files…")
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, items.isEmpty {
            FileTreeMessage(
                symbol: "exclamationmark.triangle",
                message: loadError
            )
        } else if items.isEmpty {
            FileTreeMessage(
                symbol: "folder",
                message: "This repository has no files."
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        RepositoryFileTreeRow(
                            item: item,
                            depth: 0,
                            reloadRevision: reloadRevision
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
        }
    }

    private var reloadRevision: RepositoryFileTreeRevision {
        RepositoryFileTreeRevision(
            repositoryPath: model.repositoryURL?.standardizedFileURL.path,
            automatic: model.repositoryFilesRevision
        )
    }

    private func loadRootItems() async {
        guard let repositoryURL = model.repositoryURL else {
            items = []
            loadError = nil
            return
        }

        isLoading = true
        loadError = nil
        do {
            let loaded = try await RepositoryFileLoader.loadChildren(of: repositoryURL)
            guard !Task.isCancelled,
                  model.repositoryURL == repositoryURL else {
                isLoading = false
                return
            }
            items = loaded
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            items = []
            loadError = "Could not load this repository’s files."
        }
        isLoading = false
    }
}

private struct RepositoryFileTreeRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let item: RepositoryFileTreeItem
    let depth: Int
    let reloadRevision: RepositoryFileTreeRevision

    @State private var children: [RepositoryFileTreeItem] = []
    @State private var isLoadingChildren = false
    @State private var childrenLoadFailed = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: activate) {
                rowLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(rowBackground)
            .onHover { hovering = $0 }
            .help(item.relativePath)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                }
            }

            if item.isDirectory && isExpanded {
                if isLoadingChildren && children.isEmpty {
                    childStatusRow(symbol: nil, text: "Loading…")
                } else if childrenLoadFailed && children.isEmpty {
                    childStatusRow(
                        symbol: "exclamationmark.triangle",
                        text: "Could not open folder"
                    )
                } else if children.isEmpty {
                    childStatusRow(symbol: nil, text: "Empty folder")
                } else {
                    ForEach(children) { child in
                        RepositoryFileTreeRow(
                            item: child,
                            depth: depth + 1,
                            reloadRevision: reloadRevision
                        )
                    }
                }
            }
        }
        .task(id: folderLoadRequest) {
            guard item.isDirectory, isExpanded else { return }
            await loadChildren()
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: item.isDirectory ? disclosureSymbol : "")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 11)
                .opacity(item.isDirectory ? 1 : 0)

            if item.isDirectory {
                FolderIconView(expanded: isExpanded, size: 13, width: 19)
            } else {
                FileIconView(path: item.relativePath, size: 13, width: 19)
            }

            Text(item.name)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if item.isSymbolicLink {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16 + CGFloat(depth) * 16)
        .padding(.trailing, 22)
        .frame(height: 28)
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.selection }
        return hovering ? AppTheme.hover : .clear
    }

    private var isSelected: Bool {
        !item.isDirectory
            && model.selectedRepositoryFilePath == item.relativePath
    }

    private var isExpanded: Bool {
        model.expandedFileDirectories.contains(item.relativePath)
    }

    private var disclosureSymbol: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    private var folderSymbol: String {
        isExpanded ? "folder.fill" : "folder"
    }

    private var fileSymbol: String {
        FileGlyph.symbol(forPath: item.relativePath)
    }

    private var accessibilityLabel: String {
        guard item.isDirectory else { return item.name }
        return "\(item.name), folder, \(isExpanded ? "expanded" : "collapsed")"
    }

    private var accessibilityHint: String {
        if item.isDirectory { return "Toggles this folder" }
        return isSelected ? "Closes this file" : "Opens this file"
    }

    private var folderLoadRequest: FolderLoadRequest {
        FolderLoadRequest(
            revision: reloadRevision,
            isExpanded: isExpanded
        )
    }

    private func activate() {
        if item.isDirectory {
            model.toggleFileDirectory(item.relativePath)
        } else {
            model.activateRepositoryFile(item.relativePath)
        }
    }

    private func loadChildren() async {
        isLoadingChildren = true
        childrenLoadFailed = false
        do {
            let loaded = try await RepositoryFileLoader.loadChildren(
                of: item.url,
                parentRelativePath: item.relativePath
            )
            guard !Task.isCancelled, isExpanded else {
                isLoadingChildren = false
                return
            }
            children = loaded
        } catch {
            guard !Task.isCancelled else {
                isLoadingChildren = false
                return
            }
            children = []
            childrenLoadFailed = true
        }
        isLoadingChildren = false
    }

    private func childStatusRow(symbol: String?, text: String) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10))
            } else if isLoadingChildren {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(text)
                .font(AppType.caption)

            Spacer()
        }
        .foregroundStyle(AppTheme.muted)
        .padding(.leading, 53 + CGFloat(depth) * 16)
        .padding(.trailing, 22)
        .frame(height: 26)
    }
}

private struct FolderLoadRequest: Hashable {
    let revision: RepositoryFileTreeRevision
    let isExpanded: Bool
}

private struct FileTreeMessage: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.muted)

            Text(message)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
