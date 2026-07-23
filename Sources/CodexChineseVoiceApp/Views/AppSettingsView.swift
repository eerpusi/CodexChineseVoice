import CodexChineseVoiceCore
import SwiftUI

struct AppSettingsView: View {
    let model: VoiceApplicationModel
    @AppStorage(AppPresentationPreferences.autoSendsTranscriptionKey)
    private var autoSendsTranscription = true
    @AppStorage(AppPresentationPreferences.showsDockIconKey)
    private var showsDockIcon = true
    @State private var apiKey = ""
    @State private var didSaveAPIKey = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("应用") {
                Toggle("转写完成后自动发送", isOn: $autoSendsTranscription)
                Toggle("在 Dock 中显示", isOn: $showsDockIcon)
            }

            Section("Volcengine") {
                if let maskedKey = APIKeyPresentation.maskedValue(
                    isConfigured: model.hasConfiguredAPIKey || didSaveAPIKey
                ) {
                    LabeledContent("已保存") {
                        Text(maskedKey)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("API Key 已保存")
                    }
                }
                SecureField(
                    model.hasConfiguredAPIKey || didSaveAPIKey
                        ? "输入新 Key 以替换"
                        : "API Key",
                    text: $apiKey
                )
                    .textFieldStyle(.roundedBorder)
                Button {
                    do {
                        try model.saveAPIKey(apiKey)
                        apiKey = ""
                        didSaveAPIKey = true
                        saveError = nil
                    } catch {
                        saveError = "保存配置失败"
                    }
                } label: {
                    Label("保存 Key", systemImage: "key")
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360)
        .onChange(of: showsDockIcon) { _, newValue in
            let preferences = AppPresentationPreferences(
                showsDockIcon: newValue
            )
            DockIconController.apply(preferences.activationMode)
        }
    }
}
