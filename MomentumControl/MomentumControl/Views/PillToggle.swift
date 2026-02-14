import SwiftUI

/// A custom capsule-shaped toggle with icon and optional label.
/// When off: outlined stroke, secondary color.
/// When on: filled with accent color, icon turns white, scale-up spring animation.
struct PillToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var accentColor: Color = .blue

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? accentColor : .secondary)
            .background {
                Capsule()
                    .fill(isOn ? accentColor.opacity(0.12) : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isOn ? 1.02 : 1.0)
    }
}
