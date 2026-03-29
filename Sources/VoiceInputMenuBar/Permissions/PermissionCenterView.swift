import AppKit
import SwiftUI

@MainActor
final class PermissionCenterViewModel: ObservableObject {
    @Published var snapshot: PermissionSnapshot
    @Published var diagnostics: PermissionDiagnostics
    @Published var statusMessage = ""
    @Published var requestingPermissionID: String?
    @Published var isRequestingAll = false

    private let snapshotProvider: @MainActor () -> PermissionSnapshot
    private let diagnosticsProvider: @MainActor () -> PermissionDiagnostics
    private let requestPermission: @MainActor (PermissionKind) async -> PermissionSnapshot
    private let requestAllMissing: @MainActor () async -> PermissionSnapshot
    private let openSystemSettings: @MainActor () -> Void
    private let onPermissionsChanged: @MainActor (PermissionSnapshot) -> Void

    init(
        snapshotProvider: @escaping @MainActor () -> PermissionSnapshot,
        diagnosticsProvider: @escaping @MainActor () -> PermissionDiagnostics,
        requestPermission: @escaping @MainActor (PermissionKind) async -> PermissionSnapshot,
        requestAllMissing: @escaping @MainActor () async -> PermissionSnapshot,
        openSystemSettings: @escaping @MainActor () -> Void,
        onPermissionsChanged: @escaping @MainActor (PermissionSnapshot) -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.diagnosticsProvider = diagnosticsProvider
        self.requestPermission = requestPermission
        self.requestAllMissing = requestAllMissing
        self.openSystemSettings = openSystemSettings
        self.onPermissionsChanged = onPermissionsChanged
        snapshot = snapshotProvider()
        diagnostics = diagnosticsProvider()
    }

    func reload() {
        let latest = snapshotProvider()
        snapshot = latest
        diagnostics = diagnosticsProvider()
        onPermissionsChanged(latest)
        statusMessage = latest.isReady ? "所有权限已就绪" : "请完成以下权限授权"
    }

    func request(_ permission: PermissionKind) {
        requestingPermissionID = permission.id
        statusMessage = "正在申请 \(permission.title)…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latest = await requestPermission(permission)
            snapshot = latest
            diagnostics = diagnosticsProvider()
            onPermissionsChanged(latest)
            requestingPermissionID = nil
            statusMessage = latest.isReady ? "所有权限已就绪" : "已尝试申请 \(permission.title)，如未弹窗请在系统设置中手动勾选"
        }
    }

    func requestAll() {
        isRequestingAll = true
        statusMessage = "正在依次申请权限…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latest = await requestAllMissing()
            snapshot = latest
            diagnostics = diagnosticsProvider()
            onPermissionsChanged(latest)
            isRequestingAll = false
            statusMessage = latest.isReady ? "所有权限已就绪" : "仍有权限未完成，请继续在系统设置中授权"
        }
    }

    func openSettings() {
        openSystemSettings()
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.summaryText, forType: .string)
        statusMessage = "已复制诊断信息"
    }
}

struct PermissionCenterView: View {
    @ObservedObject var viewModel: PermissionCenterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("权限中心")
                .font(.system(size: 24, weight: .semibold))

            Text("应用需要以下权限来监听 Fn、录音、转写并把文字注入当前输入框。能直接申请的权限会主动拉起；需要系统设置确认的权限可点右侧按钮继续。")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(viewModel.snapshot.items) { item in
                    permissionRow(item)
                }
            }

            HStack(spacing: 12) {
                Button("一键申请全部") {
                    viewModel.requestAll()
                }
                .disabled(viewModel.isRequestingAll)

                Button("复制诊断") {
                    viewModel.copyDiagnostics()
                }

                Button("打开系统设置") {
                    viewModel.openSettings()
                }

                Spacer()

                Text(viewModel.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            diagnosticsCard

            Spacer()
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 500)
    }

    private func permissionRow(_ item: PermissionSnapshot.Item) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(item.isGranted ? Color.green.opacity(0.9) : Color.orange.opacity(0.85))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(item.kind.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.isGranted ? "已授权" : "未授权")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.isGranted ? Color.green : Color.orange)
                .frame(width: 56, alignment: .trailing)

            Button(item.isGranted ? "复查" : "申请") {
                viewModel.request(item.kind)
            }
            .disabled(viewModel.requestingPermissionID != nil || viewModel.isRequestingAll)
            .frame(width: 72)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
        )
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("权限诊断")
                .font(.system(size: 15, weight: .semibold))

            Text("如果你已经勾选但这里仍显示未授权，通常是因为授权后没有彻底重启应用，或者你刚刚重新安装/重新签名了另一份 app。请确认当前运行路径就是下面这一份。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(viewModel.diagnostics.summaryText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
        )
    }
}
