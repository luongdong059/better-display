import DisplayCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Màn hình").font(.headline)

            if state.rows.isEmpty {
                Text("Không phát hiện màn hình nào")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.rows) { row in
                    DisplayRowView(row: row)
                }
            }

            if let error = state.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Khởi động cùng máy", isOn: $state.launchAtLogin)

            Divider()

            HStack {
                Button("Bật tất cả màn hình") { state.restoreAll() }
                    .help("Cứu hộ: bật lại mọi màn hình đã tắt và reset gamma")
                Spacer()
                Button("Thoát") { NSApp.terminate(nil) }
            }

            HStack {
                Text("Design by Dong")
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct DisplayRowView: View {
    @EnvironmentObject private var state: AppState
    let row: AppState.Row

    private var subtitle: String {
        if row.isGhost { return "Đã tắt (disconnect)" }
        var parts: [String] = []
        if row.info.resolution.width > 0 {
            parts.append("\(Int(row.info.resolution.width))×\(Int(row.info.resolution.height))")
        }
        if row.info.refreshRate > 0 {
            parts.append("\(Int(row.info.refreshRate.rounded()))Hz")
        }
        if row.info.isMain { parts.append("màn hình chính") }
        if row.info.isMirrored { parts.append("mirror") }
        if !row.info.isEnabled { parts.append("đang tắt") }
        return parts.joined(separator: " • ")
    }

    private var isLocked: Bool { state.isLastActive(row) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.info.isBuiltin ? "laptopcomputer" : "display")
                .foregroundStyle(row.info.isEnabled ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.info.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { row.info.isEnabled },
                set: { state.setPower($0, for: row) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(isLocked)
                .help(isLocked
                    ? "Không thể tắt màn hình đang hoạt động cuối cùng"
                    : (row.info.isEnabled ? "Tắt màn hình này" : "Bật lại màn hình này"))

            if !row.isGhost {
                Menu {
                    Picker("Cách tắt", selection: Binding(
                        get: { state.preferredStrategies[row.info.persistentKey] },
                        set: { state.setPreferredStrategy($0, for: row) })) {
                        Text("Tự động (Disconnect)").tag(StrategyKind?.none)
                        Text("Disconnect — macOS coi như rút cáp").tag(StrategyKind?.some(.disconnect))
                        if row.info.supportsDDC {
                            Text("DDC — tắt nguồn thật (standby)").tag(StrategyKind?.some(.ddc))
                        }
                        Text("Gamma — màn đen, vẫn sáng đèn").tag(StrategyKind?.some(.gamma))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
                .help("Chọn cách tắt cho màn hình này")
            }
        }
    }
}
