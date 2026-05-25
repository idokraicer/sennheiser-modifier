import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: HeadphoneViewModel
    @State private var isMoreExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.connectionStatus.isConnected {
                connectedContent
            } else {
                DeviceScannerView(viewModel: viewModel)
                    .padding(12)
            }

            // Footer
            HStack {
                if viewModel.state.connectionStatus.isConnected {
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// The connected-state content. Wrapped in a fixed-height ScrollView only
    /// when "More" is expanded, since that's the only state where content can
    /// overflow. Otherwise we use intrinsic sizing — `ScrollView` inside
    /// `MenuBarExtra(.window)` collapses to 0 height without an explicit frame.
    @ViewBuilder
    private var connectedContent: some View {
        if isMoreExpanded {
            ScrollView(.vertical, showsIndicators: false) {
                mainStack
            }
            .frame(height: 540)
        } else {
            mainStack
        }
    }

    private var mainStack: some View {
        VStack(spacing: 12) {
            DeviceHeaderView(state: viewModel.state)
            ANCControlView(viewModel: viewModel)
            QuickTogglesView(viewModel: viewModel)

            ExpandableSection(
                title: "More",
                isExpanded: $isMoreExpanded
            ) {
                VStack(spacing: 10) {
                    ConnectedDevicesView(viewModel: viewModel)
                    SettingsView(viewModel: viewModel)
                }
            }
        }
        .padding(12)
    }
}
