//
//  TranslationSettingsView.swift
//  Nyora (iOS)
//
//  Dedicated settings screen for the AI page-translation feature. Mirrors the
//  macApp: pick an engine (Google / Apple Intelligence / Custom BYOK), configure
//  an OpenAI-compatible endpoint when BYOK, toggle post-MT Apple Intelligence
//  refinement, and choose source/target languages.
//

import SwiftUI

struct TranslationSettingsView: View {
    private let controller = TranslationController.shared

    @State private var enabled = TranslationController.shared.enabled
    @State private var engine = TranslationController.shared.engine
    @State private var targetLanguage = TranslationController.shared.targetLanguage
    @State private var sourceLanguage = TranslationController.shared.sourceLanguage
    @State private var useAppleIntelligence = TranslationController.shared.useAppleIntelligence

    @State private var byokEndpoint = TranslationController.shared.byokEndpoint
    @State private var byokApiKey = TranslationController.shared.byokApiKey
    @State private var byokModel = TranslationController.shared.byokModel

    @State private var appleStatus = AppleIntelligenceRefiner.shared.statusText
    @State private var appleReady = AppleIntelligenceRefiner.shared.isReady

    private var targetLanguages: [String] {
        TranslationConfig.supportedLanguages.filter { $0 != "AUTO" }
    }

    var body: some View {
        List {
            Section {
                Toggle("Translate pages", isOn: $enabled)
                    .onChange(of: enabled) { controller.enabled = $0 }
            } footer: {
                Text("Detect text in manga pages, then translate and overlay it in your reading language.")
            }

            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(TranslationEngine.allCases) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .onChange(of: engine) { controller.engine = $0 }
            } header: {
                Text("Engine")
            } footer: {
                Text(engineFooter)
            }

            if engine == .byok {
                Section {
                    HStack {
                        Text("API Endpoint")
                        Spacer()
                        TextField("https://api.openai.com/v1", text: $byokEndpoint)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .onChange(of: byokEndpoint) { controller.byokEndpoint = $0 }
                    }
                    HStack {
                        Text("API Key")
                        Spacer()
                        SecureField("sk-…", text: $byokApiKey)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: byokApiKey) { controller.byokApiKey = $0 }
                    }
                    HStack {
                        Text("Model")
                        Spacer()
                        TextField("gpt-4o-mini", text: $byokModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: byokModel) { controller.byokModel = $0 }
                    }
                } header: {
                    Text("Custom API (OpenAI-compatible)")
                } footer: {
                    if !byokEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       AIEndpointPolicy.chatCompletionsURL(baseURL: byokEndpoint) == nil {
                        Text("Use HTTPS. HTTP is allowed only for localhost, 127.0.0.1, or ::1.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Any OpenAI-compatible /chat/completions endpoint (OpenAI, Groq, Mistral, Together, Ollama, LM Studio, …). Your key is stored in this device’s Keychain only. HTTPS is required except for local loopback models.")
                    }
                }
            }

            if engine == .appleIntelligence {
                Section {
                    HStack {
                        Text("Availability")
                        Spacer()
                        Text(appleStatus)
                            .foregroundStyle(appleReady ? .green : .secondary)
                    }
                } footer: {
                    if !appleReady {
                        Text("Apple Intelligence requires iOS 26 or later on a supported device with Apple Intelligence enabled. Translation will fall back to Google until it's available.")
                    } else {
                        Text("Translation runs entirely on-device — no API key, no network.")
                    }
                }
            }

            Section {
                Toggle("Refine with Apple Intelligence", isOn: $useAppleIntelligence)
                    .disabled(!appleReady)
                    .onChange(of: useAppleIntelligence) { controller.useAppleIntelligence = $0 }
            } footer: {
                if appleReady {
                    Text("After translating, rewrite each line on-device for more natural, concise speech-bubble wording.")
                } else {
                    Text("Post-translation on-device polish. Requires iOS 26+ with Apple Intelligence enabled.")
                }
            }

            Section {
                Picker("Translate to", selection: $targetLanguage) {
                    ForEach(targetLanguages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .onChange(of: targetLanguage) { controller.targetLanguage = $0 }

                Picker("Source language", selection: $sourceLanguage) {
                    ForEach(TranslationConfig.supportedLanguages, id: \.self) { lang in
                        Text(lang == "AUTO" ? "Auto-detect" : lang).tag(lang)
                    }
                }
                .onChange(of: sourceLanguage) { controller.sourceLanguage = $0 }
            } header: {
                Text("Languages")
            }
        }
        .navigationTitle("Translation")
        .onAppear {
            AppleIntelligenceRefiner.shared.refreshAvailability()
            appleStatus = AppleIntelligenceRefiner.shared.statusText
            appleReady = AppleIntelligenceRefiner.shared.isReady
        }
    }

    private var engineFooter: String {
        switch engine {
        case .google:
            return "Fast, free machine translation. No key required."
        case .appleIntelligence:
            return "On-device translation with Apple Intelligence. Private and free; requires iOS 26+."
        case .byok:
            return "Use your own large-language-model API for the highest-quality, context-aware translation."
        }
    }
}
