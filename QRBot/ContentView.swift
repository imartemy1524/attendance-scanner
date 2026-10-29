import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TelegramModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingScanner = false
    @State private var showingPaste = false
    @State private var confirmingErase = false
    @State private var pastedLink = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 34)).foregroundStyle(.blue)
                            .frame(width: 62, height: 62)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Scan. Review. Send.").font(.headline)
                            Text("Send a QR code’s start value to your Telegram bot.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }

                Section("Destination") {
                    if AppConfiguration.isConfigured {
                        Label("@\(AppConfiguration.botUsername)", systemImage: "paperplane.fill")
                    } else {
                        Label("Bot needs configuration", systemImage: "wrench.and.screwdriver")
                        Text("Set botUsername in AppConfiguration.swift before building.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !model.hasCredentials {
                    CredentialSetupView(model: model)
                } else {
                    Section("Telegram account") {
                        accountContent
                    }
                }

                if model.stage == .ready {
                    Section {
                        Button { showingScanner = true } label: {
                            Label("Scan QR code", systemImage: "qrcode.viewfinder")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .disabled(!AppConfiguration.isConfigured || model.busy)
                        Button("Enter a link manually") { showingPaste = true }
                            .disabled(!AppConfiguration.isConfigured || model.busy)
                    } footer: {
                        Text("You’ll review the start value before sending it.")
                    }
                }

                if let preview = model.preview {
                    Section("Ready to send") {
                        LabeledContent("To", value: "@\(preview.username)")
                        Text(preview.message).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button { Task { await model.send() } } label: {
                            Label("Send to bot", systemImage: "paperplane.fill")
                        }.disabled(model.busy || model.stage != .ready)
                    }
                }
                if let delivery = model.delivery {
                    Section { Text(delivery).accessibilityLabel("Delivery status: \(delivery)") }
                }

                if model.hasCredentials {
                    Section {
                        Button(model.stage == .ready ? "Sign out and erase account" : "Erase local account", role: .destructive) {
                            confirmingErase = true
                        }.disabled(model.busy || model.stage == .closing || model.stage == .starting)
                    } footer: {
                        Text("Saved credentials stay hidden. This device’s passcode or biometrics are required to unlock the account and send.")
                    }
                }
            }
            .navigationTitle("QR to Telegram")
            .overlay { if scenePhase != .active { PrivacyCover() } }
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    QRScanner(onScan: { value in
                        showingScanner = false
                        if scenePhase == .active { model.scanned(value) }
                    }, onError: { message in
                        showingScanner = false
                        model.errorMessage = message
                    })
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan a bot QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingScanner = false } } }
                }
                .overlay { if scenePhase != .active { PrivacyCover() } }
            }
            .sheet(isPresented: $showingPaste, onDismiss: { pastedLink = "" }) {
                NavigationStack {
                    Form {
                        TextField("https://t.me/your_bot?start=…", text: $pastedLink, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Review link") {
                            model.scanned(pastedLink)
                            pastedLink = ""
                            showingPaste = false
                        }.disabled(pastedLink.isEmpty)
                    }
                    .navigationTitle("Enter QR link")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPaste = false } } }
                }
                .overlay { if scenePhase != .active { PrivacyCover() } }
            }
            .alert("Couldn’t complete the action", isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
            )) { Button("OK") { model.errorMessage = nil } }
                message: { Text(model.errorMessage ?? "") }
            .confirmationDialog("Remove this account?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase account", role: .destructive) { Task { await model.eraseAccount() } }
            } message: {
                Text(model.stage == .ready
                     ? "Sign out of this app and delete its saved credentials and local session."
                     : "Delete the saved credentials and local session. To revoke the session on Telegram, use Settings → Devices in Telegram.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    showingScanner = false
                    showingPaste = false
                    pastedLink = ""
                    model.background()
                }
            }
        }.privacySensitive()
    }

    @ViewBuilder private var accountContent: some View {
        switch model.stage {
        case .locked:
            Label("Account locked", systemImage: "lock.fill")
            Button("Unlock Telegram") { Task { await model.unlock() } }.disabled(model.busy)
        case .starting, .closing:
            HStack { ProgressView(); Text(model.stage == .starting ? "Opening secure session…" : "Closing session…") }
        case .ready:
            Label("Connected", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            Button("Lock account") { Task { await model.lock() } }.disabled(model.busy)
        case .unsupported:
            Text("Telegram requested an extra sign-in step this app does not support. Complete account setup in the official Telegram app, then lock and retry.")
            Button("Lock account") { Task { await model.lock() } }
        default:
            LoginStepView(model: model).id(model.stage)
        }
    }
}

private struct CredentialSetupView: View {
    @ObservedObject var model: TelegramModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var apiID = ""
    @State private var apiHash = ""

    var body: some View {
        Section {
            SecureField("API ID", text: $apiID).keyboardType(.numberPad).textContentType(.none)
            SecureField("API hash", text: $apiHash).textContentType(.none)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save securely") {
                model.save(apiID: apiID, apiHash: apiHash)
                apiID = ""
                apiHash = ""
            }.disabled(apiID.isEmpty || apiHash.isEmpty)
            Link("Get API credentials from Telegram", destination: URL(string: "https://my.telegram.org/apps")!)
        } header: { Text("Set up Telegram") }
        footer: {
            Text("Use your own API ID and API hash. After saving, sign in with your phone number and Telegram code. Saved values cannot be displayed or exported from this app.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { apiID = ""; apiHash = "" }
        }
    }
}

private struct LoginStepView: View {
    @ObservedObject var model: TelegramModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var value = ""

    private var label: String {
        switch model.stage {
        case .phone: "Phone number, including country code"
        case .password: "Telegram two-step password"
        case .email: "Sign-in email address"
        case .emailCode: "Email verification code"
        default: "Telegram login code"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            if model.stage == .password {
                SecureField(label, text: $value).textContentType(.password)
            } else if model.stage == .phone {
                TextField("+…", text: $value).keyboardType(.phonePad).textContentType(.telephoneNumber)
            } else if model.stage == .email {
                TextField("Email", text: $value).keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } else {
                SecureField(label, text: $value).keyboardType(.numberPad).textContentType(.oneTimeCode)
            }
            Button("Continue") {
                let input = value
                value = ""
                Task { await model.authenticate(input) }
            }.disabled(value.isEmpty || model.busy)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { value = "" } }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Label("QR to Telegram", systemImage: "lock.shield.fill").font(.title2)
        }.accessibilityLabel("App content hidden")
    }
}

