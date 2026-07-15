import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MacPaste 设置")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("开机自启")
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { settings.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                if let error = settings.lastLaunchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("保存时长")
                    Spacer()
                    Picker("", selection: $settings.retentionDays) {
                        ForEach(settings.retentionOptions, id: \.self) { days in
                            Text(retentionTitle(days)).tag(days)
                        }
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("保存条数")
                    Spacer()
                    Picker("", selection: $settings.retentionCount) {
                        ForEach(settings.retentionCountOptions, id: \.self) { count in
                            Text(retentionCountTitle(count)).tag(count)
                        }
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("全局快捷键")
                    Spacer()
                    HotkeyRecorder(settings: settings)
                        .frame(width: 200, alignment: .trailing)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("直接粘贴")
                        Text(settings.accessibilityTrusted ? "辅助功能权限已开启。" : "开启辅助功能权限后，可直接粘贴到当前应用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("打开权限提示") {
                        settings.requestAccessibilityPermission()
                    }
                }

                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))

            Spacer()
        }
        .padding(22)
        .frame(width: 500, height: 300)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private func retentionTitle(_ days: Int) -> String {
        days == 1 ? "1 天" : "\(days) 天"
    }

    private func retentionCountTitle(_ count: Int) -> String {
        "\(count) 条"
    }
}

private struct HotkeyRecorder: View {
    @ObservedObject var settings: SettingsStore
    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack {
                Image(systemName: isRecording ? "record.circle" : "keyboard")
                Text(isRecording ? "请按快捷键..." : settings.hotkeyDescription)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                return nil
            }

            settings.hotkeyKeyCode = UInt32(event.keyCode)
            settings.hotkeyModifiers = modifiers
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecording = false
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= HotkeyModifierFlags.command }
        if flags.contains(.shift) { result |= HotkeyModifierFlags.shift }
        if flags.contains(.option) { result |= HotkeyModifierFlags.option }
        if flags.contains(.control) { result |= HotkeyModifierFlags.control }
        return result
    }
}
