//
//  ReaderControlsConfigView.swift
//  Aidoku
//
//  Multi-select of which reader control buttons appear (NP-022).
//

import SwiftUI

struct ReaderControlsConfigView: View {
    @State private var enabled: Set<ReaderControl>

    init() {
        self._enabled = State(initialValue: ReaderControlSettings.current)
    }

    var body: some View {
        List {
            Section {
                ForEach(ReaderControl.allCases, id: \.rawValue) { control in
                    Toggle(isOn: bindingFor(control)) {
                        Label {
                            Text(control.title)
                        } icon: {
                            Image(systemName: control.systemImage)
                        }
                    }
                }
            } footer: {
                Text(NSLocalizedString("READER_CONTROLS_FOOTER"))
            }
        }
        .navigationTitle(NSLocalizedString("READER_CONTROLS"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bindingFor(_ control: ReaderControl) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(control) },
            set: { newValue in
                if newValue {
                    enabled.insert(control)
                } else {
                    enabled.remove(control)
                }
                ReaderControlSettings.save(enabled)
            }
        )
    }
}
