import CodexChineseVoiceCore
import SwiftUI

struct AppSettingsView: View {
    let model: VoiceApplicationModel
    @AppStorage(AppPresentationPreferences.autoSendsTranscriptionKey)
    private var autoSendsTranscription = false
    @AppStorage(AppPresentationPreferences.showsDockIconKey)
    private var showsDockIcon = true
    @State private var apiKey = ""
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: SettingsWindowLayout.panelSpacing) {
            toggleRow("转写完成后自动发送", isOn: $autoSendsTranscription)
            toggleRow("在 Dock 中显示", isOn: $showsDockIcon)

            Divider()

            HStack(alignment: .center, spacing: 8) {
                Text(SettingsWindowLayout.apiKeyLabel)
                    .fixedSize()
                SecureField(
                    "",
                    text: $apiKey,
                    prompt: Text(APIKeyPresentation.inputPrompt(
                        isConfigured: model.hasConfiguredAPIKey
                    ))
                )
                .textFieldStyle(.roundedBorder)
                .frame(
                    minWidth: SettingsWindowLayout.apiKeyInputWidth,
                    maxWidth: .infinity
                )
                .layoutPriority(1)
                .onSubmit(saveAPIKey)
                Button("保存", action: saveAPIKey)
                    .buttonStyle(.borderedProminent)
                    .frame(width: 52)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsWindowLayout.rowHeight,
                alignment: .leading
            )

            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(16)
        .frame(width: SettingsWindowLayout.width)
        .onChange(of: showsDockIcon) { _, newValue in
            let preferences = AppPresentationPreferences(
                showsDockIcon: newValue
            )
            DockIconController.apply(preferences.activationMode)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 0) {
            Text(title)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: SettingsWindowLayout.toggleControlWidth)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsWindowLayout.rowHeight,
            alignment: .leading
        )
    }

    private func saveAPIKey() {
        do {
            try model.saveAPIKey(apiKey)
            apiKey = ""
            saveError = nil
        } catch {
            saveError = "保存配置失败"
        }
    }
}
