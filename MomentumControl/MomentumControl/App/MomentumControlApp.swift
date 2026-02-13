import SwiftUI

@main
struct MomentumControlApp: App {
    @State private var viewModel = HeadphoneViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(viewModel: viewModel)
                .frame(width: 320)
        } label: {
            MenuBarIcon(state: viewModel.state)
        }
        .menuBarExtraStyle(.window)
    }
}
