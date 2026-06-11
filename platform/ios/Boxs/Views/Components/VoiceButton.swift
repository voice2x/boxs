import SwiftUI

/// 浮动语音按钮 — 40pt 圆形，铁锈红背景，脉冲动画
struct VoiceButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.4

    @Environment(\.appColors) private var c

    var body: some View {
        ZStack {
            // 脉冲波纹
            if isPressed {
                Circle()
                    .stroke(c.primary.opacity(pulseOpacity), lineWidth: 2)
                    .frame(
                        width: Sz.voiceIdle * pulseScale,
                        height: Sz.voiceIdle * pulseScale
                    )
                    .onAppear { startPulse() }
                    .onDisappear { stopPulse() }
            }

            // 按钮本体
            Button(action: onTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(
                        width: isPressed ? Sz.voiceActive : Sz.voiceIdle,
                        height: isPressed ? Sz.voiceActive : Sz.voiceIdle
                    )
                    .background(c.primary)
                    .clipShape(Circle())
            }
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in onLongPress() }
            )
            .onLongPressGesture(
                minimumDuration: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPressed = pressing
                    }
                },
                perform: {}
            )
        }
        .padding(.bottom, 20)
    }

    private func startPulse() {
        withAnimation(
            .easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            pulseScale = 1.6
            pulseOpacity = 0
        }
    }

    private func stopPulse() {
        pulseScale = 1.0
        pulseOpacity = 0.4
    }
}
