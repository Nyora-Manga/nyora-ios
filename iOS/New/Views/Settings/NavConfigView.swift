//
//  NavConfigView.swift
//  Aidoku
//
//  Main-screen navigation config (NP-029): reorder / enable bottom tab sections.
//

import SwiftUI

struct NavConfigView: View {
    @State private var sections: [NavSection]
    @State private var enabled: Set<NavSection>

    init() {
        let enabledList = NavConfig.enabledSections
        // enabled sections first (in stored order), then any disabled ones
        let disabled = NavSection.allCases.filter { !enabledList.contains($0) }
        self._sections = State(initialValue: enabledList + disabled)
        self._enabled = State(initialValue: Set(enabledList))
    }

    var body: some View {
        List {
            Section {
                ForEach(sections, id: \.rawValue) { section in
                    Toggle(isOn: bindingFor(section)) {
                        Label {
                            Text(section.title)
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                    }
                    .disabled(section.isRequired)
                }
                .onMove(perform: move)
            } footer: {
                Text(NSLocalizedString("NAV_CONFIG_FOOTER"))
            }
        }
        .navigationTitle(NSLocalizedString("NAV_CONFIG"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func bindingFor(_ section: NavSection) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(section) || section.isRequired },
            set: { newValue in
                if newValue {
                    enabled.insert(section)
                } else if !section.isRequired {
                    enabled.remove(section)
                }
                persist()
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        let ordered = sections.filter { enabled.contains($0) || $0.isRequired }
        NavConfig.save(ordered)
    }
}
