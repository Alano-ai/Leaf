// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct DeepSeekSettings: View {
    @State private var key = ""
    @State private var hasKey = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("DeepSeek API Key", text: $key)
                    .onSubmit { if !key.isEmpty { save() } }
                LabeledContent("Keychain", value: hasKey ? String(localized: "Key saved") : String(localized: "No key saved"))
                HStack {
                    Button("Save Key", action: save)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if hasKey {
                        Button("Remove Key", role: .destructive, action: remove)
                    }
                }
            } header: {
                Text("DeepSeek")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Leaf stores the key in your Mac’s Keychain. DeepSeek analysis runs only when you request it from the converter.")
                    Link("Manage DeepSeek API keys", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .task {
            do { hasKey = try DeepSeekKeychain.hasKey() }
            catch { message = error.localizedDescription }
        }
        .alert("DeepSeek", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: message ?? "")
        }
    }

    private func save() {
        do {
            try DeepSeekKeychain.save(key)
            key = ""
            hasKey = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try DeepSeekKeychain.remove()
            hasKey = false
            key = ""
        } catch {
            message = error.localizedDescription
        }
    }
}
