import SwiftUI
import CodexChineseVoiceCore

struct MenuBarInputLevelView: View {
    let isRecording: Bool
    let level: Double

    private let weights = [0.45, 0.75, 1.0, 0.65]

    private var presentation: MenuBarIndicatorPresentation {
        MenuBarIndicatorPresentation(isRecording: isRecording, level: level)
    }

    var body: some View {
        Group {
            if presentation.showsMeter {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(weights.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.red)
                            .frame(
                                width: 3,
                                height: barHeight(weight: weights[index])
                            )
                    }
                }
            } else {
                Image(systemName: presentation.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(
            width: presentation.reservedWidth,
            height: 18,
            alignment: .center
        )
        .fixedSize()
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel(
            isRecording ? "CodexChineseVoice 正在录音" : "CodexChineseVoice"
        )
        .help(isRecording ? "正在录音" : "CodexChineseVoice")
    }

    private func barHeight(weight: Double) -> Double {
        return 3 + 14 * presentation.normalizedLevel * weight
    }
}
