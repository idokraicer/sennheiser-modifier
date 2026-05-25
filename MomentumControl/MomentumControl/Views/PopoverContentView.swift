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

    private var connectedContent: some View {
        mainStack
    }

    private var mainStack: some View {
        VStack(spacing: 12) {
            DeviceHeaderView(state: viewModel.state)
            ANCControlView(viewModel: viewModel)

            ExpandableSection(
                title: "More",
                isExpanded: $isMoreExpanded
            ) {
                ConnectedDevicesView(viewModel: viewModel)
            }
        }
        .padding(12)
    }
}
