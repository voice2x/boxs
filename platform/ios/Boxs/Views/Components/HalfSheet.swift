import SwiftUI

/// 自定义半屏弹窗
struct HalfSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content

    @Environment(\.appColors) private var c

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            ZStack {
                // 遮罩
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }

                // 弹窗内容
                VStack(spacing: 0) {
                    // 把手
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    content
                }
                .background(c.surface)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: R.bottomSheet,
                        topTrailingRadius: R.bottomSheet
                    )
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .transition(.move(edge: .bottom))
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
    }
}
