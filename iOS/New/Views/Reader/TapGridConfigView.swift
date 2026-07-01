//
//  TapGridConfigView.swift
//  Aidoku
//
//  Configuration screen for the 3x3 reader tap grid (NP-007).
//

import SwiftUI

struct TapGridConfigView: View {
    @State private var mapping: [TapGridArea: TapGridAction]
    @State private var longMapping: [TapGridArea: TapGridAction]

    init() {
        self._mapping = State(initialValue: TapGridSettings.currentMapping())
        self._longMapping = State(initialValue: TapGridSettings.currentLongMapping())
    }

    private static let spacing: CGFloat = 6

    var body: some View {
        List {
            Section {
                gridView
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } header: {
                Text(NSLocalizedString("TAP_GRID"))
            } footer: {
                Text(NSLocalizedString("TAP_GRID_FOOTER"))
            }

            Section {
                ForEach(TapGridArea.allCases, id: \.rawValue) { area in
                    Picker(selection: bindingFor(area)) {
                        ForEach(TapGridAction.allCases, id: \.rawValue) { action in
                            Text(action.title).tag(action)
                        }
                    } label: {
                        Text(areaTitle(area))
                    }
                }
            } header: {
                Text(NSLocalizedString("ZONES"))
            }

            Section {
                ForEach(TapGridArea.allCases, id: \.rawValue) { area in
                    Picker(selection: longBindingFor(area)) {
                        ForEach(TapGridAction.allCases, id: \.rawValue) { action in
                            Text(action.title).tag(action)
                        }
                    } label: {
                        Text(areaTitle(area))
                    }
                }
            } header: {
                Text(NSLocalizedString("LONG_PRESS_ZONES"))
            } footer: {
                Text(NSLocalizedString("LONG_PRESS_ZONES_FOOTER"))
            }

            Section {
                Button(role: .destructive) {
                    TapGridSettings.reset()
                    mapping = TapGridSettings.currentMapping()
                    longMapping = TapGridSettings.currentLongMapping()
                    notifyChange()
                } label: {
                    Text(NSLocalizedString("RESET_TO_DEFAULT"))
                }
            }
        }
        .navigationTitle(NSLocalizedString("TAP_GRID"))
    }

    private var gridView: some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let area = TapGridArea(row: row, col: col)
                        let action = mapping[area] ?? .none
                        cell(action: action)
                    }
                }
            }
        }
        .aspectRatio(3/4, contentMode: .fit)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }

    private func cell(action: TapGridAction) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color(for: action).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color(for: action).opacity(0.6), lineWidth: 1)
            )
            .overlay(
                Text(action.title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(2)
                    .minimumScaleFactor(0.6)
            )
    }

    private func color(for action: TapGridAction) -> Color {
        let hex = action.colorHex
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private func bindingFor(_ area: TapGridArea) -> Binding<TapGridAction> {
        Binding(
            get: { mapping[area] ?? .none },
            set: { newValue in
                mapping[area] = newValue
                TapGridSettings.setAction(newValue, for: area)
                notifyChange()
            }
        )
    }

    private func longBindingFor(_ area: TapGridArea) -> Binding<TapGridAction> {
        Binding(
            get: { longMapping[area] ?? .none },
            set: { newValue in
                longMapping[area] = newValue
                TapGridSettings.setLongAction(newValue, for: area)
                notifyChange()
            }
        )
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .init("Reader.tapGrid"), object: nil)
    }

    private func areaTitle(_ area: TapGridArea) -> String {
        let rows = [
            NSLocalizedString("ZONE_TOP"),
            NSLocalizedString("ZONE_MIDDLE"),
            NSLocalizedString("ZONE_BOTTOM")
        ]
        let cols = [
            NSLocalizedString("ZONE_LEFT"),
            NSLocalizedString("ZONE_CENTER"),
            NSLocalizedString("ZONE_RIGHT")
        ]
        return "\(rows[area.row]) \(cols[area.col])"
    }
}

#Preview {
    PlatformNavigationStack {
        TapGridConfigView()
    }
}
