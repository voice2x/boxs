import SwiftUI

@main
struct BoxsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appColors: AppColors = .light

    var body: some Scene {
        WindowGroup {
            MainPage()
                .environment(\.appColors, appColors)
                .preferredColorScheme(.dark)
                .onAppear {
                    // 根据系统外观自动切换主题
                    updateTheme()
                }
        }
    }

    private func updateTheme() {
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        appColors = style == .dark ? .dark : .light
    }
}
