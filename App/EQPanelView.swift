import SwiftUI
import ToneCore

struct EQPanelView: View {
    @ObservedObject var model: AppModel

    private let range = -12.0 ... 12.0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            if let message = model.errorMessage {
                errorBanner(message)
            }

            ResponseCurve(profile: model.profile, range: range)
                .frame(height: 58)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            faders
            presets

            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: 430)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.isEnabled }, set: { _ in model.toggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceName)
                    .font(Theme.title)
                    .foregroundStyle(Theme.text)
                Text(model.isEnabled
                     ? String(format: "equalizing · +%.0f ms · preamp %.1f dB", model.latencyMilliseconds, model.preampDB)
                     : "off · system audio untouched")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textDim)
            }

            Spacer()

            Button("Flat") { model.reset() }
                .buttonStyle(.plain)
                .font(Theme.label)
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.panelRaised)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(Theme.label)
            .foregroundStyle(Theme.boost)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.boost.opacity(0.09))
    }

    private var faders: some View {
        HStack(spacing: 4) {
            ForEach($model.profile.bands) { $band in
                BandFader(
                    frequency: band.frequency,
                    gain: $band.gain,
                    range: range,
                    onChange: model.profileChanged
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Presets.all) { preset in
                    let isCurrent = preset.name == model.profile.name
                    Button(preset.name) { model.apply(preset: preset) }
                        .buttonStyle(.plain)
                        .font(Theme.label)
                        .foregroundStyle(isCurrent ? Theme.panel : Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isCurrent ? Theme.neutral : Theme.panelRaised)
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        )
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("double-click a fader to zero it")
                .font(Theme.label)
                .foregroundStyle(Theme.textDim.opacity(0.7))
            Spacer()
            Toggle("Start at login", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.set($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.mini)
            .font(Theme.label)
            .foregroundStyle(Theme.textDim)

            Button("Import AutoEQ…") { importAutoEQ() }
                .buttonStyle(.plain)
                .font(Theme.label)
                .foregroundStyle(Theme.textDim)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.label)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func importAutoEQ() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an AutoEQ ParametricEQ export for your headphones."
        // The menu-bar popover closes the moment focus moves, so the panel has to be
        // brought to the front deliberately.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importAutoEQ(from: url)
    }
}
