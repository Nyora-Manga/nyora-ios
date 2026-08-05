//
//  BackupsView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct BackupsView: View {
    @State private var backupUrls: [URL] = []
    @State private var backups: [URL: Backup] = [:]
    @State private var invalidBackups: Set<URL> = []

    @State private var loadedInitialBackupInfo = false
    @State private var targetRestoreBackup: Backup?
    @State private var targetExportBackup: Backup?
    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    @State private var showAutoBackupsSheet = false
    @State private var showImportFailAlert = false
    @State private var showMihonImportSheet = false
    @State private var mihonExportURL: URL?
    @State private var mihonMessage: String?
    @State private var mihonBusy = false
    @State private var mihonMissingCount = 0

    @EnvironmentObject private var path: NavigationCoordinator

    @Namespace private var transitionNamespace

    private enum SheetID: String {
        case autoBackup
    }

    init() {
        self._backupUrls = State(initialValue: BackupManager.backupUrls)
    }

    var body: some View {
        let list = List {
            Section {
                ForEach(backupUrls, id: \.self) { url in
                    let backup = backups[url]

                    if let backup {
                        backupCell(url: url, backup: backup)
                    } else if invalidBackups.contains(url) {
                        Text(NSLocalizedString("CORRUPTED_BACKUP"))
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .onDelete(perform: onDelete)
            } footer: {
                if !backupUrls.isEmpty {
                    Text(NSLocalizedString("BACKUP_INFO"))
                }
            }
        }
        .animation(.default, value: backupUrls)
        .animation(.default, value: backups)
        .navigationTitle(NSLocalizedString("BACKUPS"))
        .sheet(isPresented: $showCreateSheet) {
            BackupCreateView()
        }
        .sheet(isPresented: $showImportSheet) {
            DocumentPickerView(
                allowedContentTypes: [
                    .init(filenameExtension: "aib")!,
                    .init(filenameExtension: MihonBackupManager.fileExtension)!,
                    .json
                ],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else {
                        return
                    }
                    // A .tachibk is a Mihon backup; anything else is the app's own format.
                    if url.pathExtension.lowercased() == MihonBackupManager.fileExtension {
                        importMihonBackup(from: url)
                        return
                    }
                    Task {
                        let result = await BackupManager.shared.importBackup(from: url)
                        if !result {
                            showImportFailAlert = true
                        }
                    }
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAutoBackupsSheet) {
            AutomaticBackupsView()
                .navigationTransitionZoom(sourceID: SheetID.autoBackup, in: transitionNamespace)
        }
        .sheet(item: $targetRestoreBackup) { backup in
            BackupContentView(backup: backup)
        }
        .sheet(isPresented: $showMihonImportSheet) {
            DocumentPickerView(
                allowedContentTypes: [
                    .init(filenameExtension: MihonBackupManager.fileExtension)!,
                    .data
                ],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else { return }
                    importMihonBackup(from: url)
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $mihonExportURL) { url in
            ActivityViewController(activityItems: [url])
                .ignoresSafeArea()
        }
        .alert(
            NSLocalizedString("MIHON_BACKUP"),
            isPresented: Binding(get: { mihonMessage != nil }, set: { if !$0 { mihonMessage = nil } })
        ) {
            if mihonMissingCount > 0 {
                Button(NSLocalizedString("MIHON_VIEW_MISSING_SOURCE")) {
                    mihonMessage = nil
                    // Open the library filtered to the bucket of unbound entries.
                    NotificationCenter.default.post(
                        name: .openLibraryCategory,
                        object: MihonBackupManager.missingSourceCategory
                    )
                }
            }
            Button(NSLocalizedString("OK"), role: .cancel) { mihonMessage = nil }
        } message: {
            Text(mihonMessage ?? "")
        }
        .alert(NSLocalizedString("IMPORT_FAIL"), isPresented: $showImportFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT"))
        }
        .onAppear {
            guard !loadedInitialBackupInfo else { return }
            loadedInitialBackupInfo = true
            loadBackupInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateBackupList)) { _ in
            backupUrls = BackupManager.backupUrls
            loadBackupInfo()
        }

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        autoBackupButton
                        createBackupButton
                    }
                }
        }
    }

    var autoBackupButton: some View {
        Button {
            showAutoBackupsSheet = true
        } label: {
            let imageName = if #available(iOS 18.0, *) {
                "clock.arrow.trianglehead.counterclockwise.rotate.90"
            } else {
                "clock.arrow.circlepath"
            }
            Image(systemName: imageName)
        }
        .matchedTransitionSourcePlease(id: SheetID.autoBackup, in: transitionNamespace)
    }

    var createBackupButton: some View {
        Menu {
            Button {
                showCreateSheet = true
            } label: {
                Label(NSLocalizedString("CREATE_BACKUP"), systemImage: "plus")
            }
            Button {
                showImportSheet = true
            } label: {
                Label(NSLocalizedString("IMPORT_BACKUP"), systemImage: "square.and.arrow.down")
            }
            Divider()
            Button {
                exportMihonBackup()
            } label: {
                Label(NSLocalizedString("EXPORT_MIHON_BACKUP"), systemImage: "arrow.up.doc")
            }
            .disabled(mihonBusy)
            Button {
                showMihonImportSheet = true
            } label: {
                Label(NSLocalizedString("IMPORT_MIHON_BACKUP"), systemImage: "arrow.down.doc")
            }
            .disabled(mihonBusy)
        } label: {
            Image(systemName: "plus")
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            autoBackupButton
        }

        ToolbarSpacer(placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            createBackupButton
        }
    }

    // MARK: - Mihon (.tachibk) backup

    /// Writes a Mihon-compatible backup and offers it via the share sheet.
    ///
    /// This is the migration path in and out of the app, so it is deliberately
    /// reachable without any account or network: the file is produced locally and
    /// handed straight to the system share sheet.
    private func exportMihonBackup() {
        mihonBusy = true
        Task {
            do {
                let data = try await MihonBackupManager.shared.export()
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd_HH-mm"
                let name = "nyora_\(stamp.string(from: Date())).\(MihonBackupManager.fileExtension)"
                // The app shadows `temporaryDirectory` as optional; fall back to
                // the documents directory so an export never silently fails.
                let directory = FileManager.default.temporaryDirectory ?? FileManager.default.documentDirectory
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                await MainActor.run {
                    mihonBusy = false
                    mihonExportURL = url
                }
            } catch {
                await MainActor.run {
                    mihonBusy = false
                    mihonMessage = error.localizedDescription
                }
            }
        }
    }

    /// Restores a Mihon backup by MERGING it into the library — nothing existing
    /// is cleared, so importing can only ever add.
    private func importMihonBackup(from url: URL) {
        mihonBusy = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let result = try await MihonBackupManager.shared.importBackup(data: data)
                await MainActor.run {
                    mihonBusy = false
                    mihonMissingCount = result.missingSourceCount
                    mihonMessage = Self.summary(for: result)
                    NotificationCenter.default.post(name: .updateLibrary, object: nil)
                }
            } catch {
                await MainActor.run {
                    mihonBusy = false
                    mihonMessage = error.localizedDescription
                }
            }
        }
    }

    private static func summary(for result: MihonImportResult) -> String {
        var lines = [
            String(format: NSLocalizedString("MIHON_IMPORT_SUMMARY"), result.manga, result.categories)
        ]
        if result.missingSourceCount > 0 {
            lines.append(String(format: NSLocalizedString("MIHON_IMPORT_PENDING"), result.missingSourceCount))
        }
        if !result.unmatchedSources.isEmpty {
            let names = result.unmatchedSources.prefix(5).joined(separator: ", ")
            let extra = result.unmatchedSources.count > 5 ? "…" : ""
            lines.append(String(format: NSLocalizedString("MIHON_IMPORT_UNMATCHED"), names + extra))
        }
        return lines.joined(separator: "\n\n")
    }

    func backupCell(url: URL, backup: Backup) -> some View {
        Button {
            targetRestoreBackup = backup
        } label: {
            HStack {
                let date = DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short)
                if let name = backup.name {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(name)
                                .lineLimit(1)
                            if backup.automatic ?? false {
                                automaticBadge
                            }
                        }
                        Text(date)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text(String(format: NSLocalizedString("BACKUP_%@"), date))
                            .lineLimit(1)
                        if backup.automatic ?? false {
                            automaticBadge
                        }
                    }
                }
                Spacer()
                if
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                    let size = attributes[FileAttributeKey.size] as? Int64
                {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button(role: .destructive) {
                onDelete(at: IndexSet(integer: backupUrls.firstIndex(of: url)!))
            } label: {
                Label(NSLocalizedString("DELETE"), systemImage: "trash")
            }
            Button {
                showRenamePrompt(targetRenameBackupUrl: url, initialName: backup.name)
            } label: {
                Label(NSLocalizedString("RENAME"), systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button {
                targetExportBackup = backup
            } label: {
                Label(NSLocalizedString("EXPORT"), systemImage: "square.and.arrow.up")
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: targetExportBackup) { newValue in
                        if newValue == backup {
                            export(url: url, sourceRect: geo.frame(in: .global))
                        }
                    }
            }
        )
    }

    var automaticBadge: some View {
        Text(NSLocalizedString("AUTO"))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.blue.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func onDelete(at offsets: IndexSet) {
        for offset in offsets {
            let url = backupUrls[offset]
            Task {
                await BackupManager.shared.removeBackup(url: url)
            }
            backups.removeValue(forKey: url)
        }
        backupUrls.remove(atOffsets: offsets)
    }

    func showRenamePrompt(targetRenameBackupUrl: URL, initialName: String?) {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("RENAME_BACKUP"),
            message: NSLocalizedString("RENAME_BACKUP_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    renameBackup(url: targetRenameBackupUrl, name: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("BACKUP_NAME")
                    textField.text = initialName
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }
}

extension BackupsView {
    func loadBackupInfo() {
        Task.detached { [backupUrls] in
            for backupUrl in backupUrls {
                let backup = Backup.load(from: backupUrl)
                await MainActor.run {
                    if let backup {
                        self.backups[backupUrl] = backup
                    } else {
                        self.invalidBackups.insert(backupUrl)
                    }
                }
            }
        }
    }

    func renameBackup(url: URL, name: String) {
        Task {
            await BackupManager.shared.renameBackup(url: url, name: name)
        }
    }

    func export(url: URL, sourceRect: CGRect) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let sourceView = path.rootViewController?.view else { return }
        vc.popoverPresentationController?.sourceView = sourceView
        vc.popoverPresentationController?.sourceRect = sourceRect
        path.present(vc)
    }
}
