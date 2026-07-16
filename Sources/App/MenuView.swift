import CoreGraphics
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
                displayList
            }

            if let pending = state.pendingRevert {
                revertBanner(pending)
            }

            if let error = state.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Khởi động cùng máy", isOn: $state.launchAtLogin)

            Toggle("Phím tắt toàn cục (⌥⌘1-9, ⌥⌘0 = bật tất cả)", isOn: $state.hotkeysEnabled)

            if state.canCheckForUpdates {
                Button("Kiểm tra bản cập nhật…") { state.checkForUpdates() }
                    .buttonStyle(.link)
                    .font(.callout)
            }

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
        .frame(width: 360)
    }

    @ViewBuilder
    private var displayList: some View {
        let rows = ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
            DisplayRowView(row: row, index: index)
        }
        if state.rows.count > 3 {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { rows }
            }
            .frame(maxHeight: 420)
        } else {
            rows
        }
    }

    private func revertBanner(_ pending: AppState.PendingRevert) -> some View {
        HStack(spacing: 8) {
            Text("Đã đổi kích thước \"\(pending.displayName)\" — giữ thay đổi? (\(pending.seconds)s)")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Giữ") { state.confirmModeChange() }
            Button("Hoàn tác") { state.revertModeChange() }
        }
        .padding(8)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Một hàng màn hình (bấm chevron để xổ xuống khu điều khiển)

private struct DisplayRowView: View {
    @EnvironmentObject private var state: AppState
    let row: AppState.Row
    let index: Int
    @State private var expanded = false

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
    private var canExpand: Bool { !row.isGhost && (row.info.isEnabled || row.info.isMirrored) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canExpand)
                .opacity(canExpand ? 1 : 0.3)
                .help("Điều khiển nâng cao: độ sáng, kích thước, xoay, mirror")

                Image(systemName: row.info.isBuiltin ? "laptopcomputer" : "display")
                    .foregroundStyle(row.info.isEnabled ? .primary : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.info.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if state.hotkeysEnabled, index < 9 {
                    Text("⌥⌘\(index + 1)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .help("Phím tắt bật/tắt màn hình này")
                }

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

            if expanded, canExpand {
                DisplayControlsView(row: row)
                    .padding(.leading, 24)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Khu điều khiển nâng cao của một màn hình

private struct DisplayControlsView: View {
    @EnvironmentObject private var state: AppState
    let row: AppState.Row

    @State private var sizeChoices: [DisplaySizeChoice] = []
    @State private var sizeIndex: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.info.isEnabled {
                brightnessRow
                sizeRow
                rotationRow
            }
            mirrorRow
        }
        .controlSize(.small)
        .onAppear {
            state.loadBrightness(for: row)
            reloadSizes()
        }
        .onChange(of: row.info.resolution) { _ in reloadSizes() }
    }

    private func reloadSizes() {
        sizeChoices = state.sizeChoices(for: row)
        if let index = sizeChoices.firstIndex(where: \.isCurrent) {
            sizeIndex = Double(index)
        }
    }

    // Độ sáng
    @ViewBuilder
    private var brightnessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill").foregroundStyle(.secondary).frame(width: 16)
            if row.info.supportsDDC, let b = state.brightnessStates[row.id] {
                Slider(value: Binding(
                    get: { b.percent },
                    set: { state.setBrightness(percent: $0, for: row) }), in: 0...100)
                Text("\(Int(b.percent))%")
                    .font(.caption).monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            } else if row.info.supportsDDC {
                Slider(value: .constant(0), in: 0...100).disabled(true)
                Text("…").font(.caption).frame(width: 36, alignment: .trailing)
            } else {
                Text("Màn hình không hỗ trợ chỉnh độ sáng (DDC)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // Kích thước
    @ViewBuilder
    private var sizeRow: some View {
        if sizeChoices.count > 1 {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.secondary).frame(width: 16)
                Slider(
                    value: $sizeIndex,
                    in: 0...Double(sizeChoices.count - 1),
                    step: 1
                ) { editing in
                    guard !editing else { return }
                    let choice = sizeChoices[Int(sizeIndex)]
                    if !choice.isCurrent { state.applySize(choice, for: row) }
                }
                Text(sizeChoices.indices.contains(Int(sizeIndex)) ? sizeChoices[Int(sizeIndex)].label : "")
                    .font(.caption).monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }

    // Xoay màn hình
    @ViewBuilder
    private var rotationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.right").foregroundStyle(.secondary).frame(width: 16)
            Picker("", selection: Binding(
                get: { state.rotation(for: row) },
                set: { state.setRotation($0, for: row) })) {
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // Mirror
    @ViewBuilder
    private var mirrorRow: some View {
        let candidates = state.mirrorCandidates(for: row)
        if !candidates.isEmpty || state.mirrorMaster(for: row) != 0 {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary).frame(width: 16)
                Picker("Mirror:", selection: Binding(
                    get: { state.mirrorMaster(for: row) },
                    set: { state.setMirror(master: $0, for: row) })) {
                    Text("Tắt").tag(CGDirectDisplayID(0))
                    ForEach(candidates) { candidate in
                        Text(candidate.info.name).tag(candidate.id)
                    }
                }
                .fixedSize()
            }
        }
    }
}
