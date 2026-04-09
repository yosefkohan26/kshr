import SwiftUI

// MARK: - Popover content

struct SSHPresetsPopoverView: View {
    @ObservedObject var store: SSHPresetStore
    @State private var editingPreset: SSHPreset?
    @State private var isAdding = false
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "sshPresets.title", defaultValue: "SSH Presets"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { isAdding = true }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help(String(localized: "sshPresets.add.tooltip", defaultValue: "Add SSH preset"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            if store.presets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        .frame(width: 280)
        .sheet(isPresented: $isAdding) {
            SSHPresetFormView(
                store: store,
                preset: nil,
                onDone: { isAdding = false }
            )
        }
        .sheet(item: $editingPreset) { preset in
            SSHPresetFormView(
                store: store,
                preset: preset,
                onDone: { editingPreset = nil }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(String(localized: "sshPresets.empty", defaultValue: "No presets yet"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button(String(localized: "sshPresets.addFirst", defaultValue: "Add Preset")) {
                isAdding = true
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(kshrAccentColor())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var presetList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.presets) { preset in
                    presetRow(preset)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 300)
    }

    private func presetRow(_ preset: SSHPreset) -> some View {
        HStack(spacing: 6) {
            // Connect button (main tap area)
            Button(action: {
                store.connect(preset)
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.displayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if !preset.name.isEmpty && preset.name != preset.destination {
                            Text(preset.destination + (preset.port.map { ":\($0)" } ?? ""))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Edit button
            Button(action: { editingPreset = preset }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "sshPresets.edit.tooltip", defaultValue: "Edit preset"))

            // Delete button
            Button(action: { store.delete(preset) }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "sshPresets.delete.tooltip", defaultValue: "Delete preset"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SSHPresetRowHoverBackground())
    }
}

// MARK: - Hover background helper

private struct SSHPresetRowHoverBackground: View {
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHovered ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Add / Edit form

struct SSHPresetFormView: View {
    @ObservedObject var store: SSHPresetStore
    let preset: SSHPreset?  // nil = add mode
    let onDone: () -> Void

    @State private var name: String = ""
    @State private var destination: String = ""
    @State private var portString: String = ""
    @State private var identityFile: String = ""
    @State private var sshOptionsString: String = ""
    @State private var workspaceName: String = ""

    private var isEditing: Bool { preset != nil }

    private var isValid: Bool {
        !destination.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing
                 ? String(localized: "sshPresets.form.editTitle", defaultValue: "Edit Preset")
                 : String(localized: "sshPresets.form.addTitle", defaultValue: "New SSH Preset"))
                .font(.system(size: 13, weight: .semibold))

            formFields

            HStack {
                Button(String(localized: "sshPresets.form.cancel", defaultValue: "Cancel")) {
                    onDone()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing
                       ? String(localized: "sshPresets.form.save", defaultValue: "Save")
                       : String(localized: "sshPresets.form.add", defaultValue: "Add")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { populateFromPreset() }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledField(String(localized: "sshPresets.form.name", defaultValue: "Name")) {
                TextField(String(localized: "sshPresets.form.namePlaceholder", defaultValue: "My Server"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            LabeledField(String(localized: "sshPresets.form.destination", defaultValue: "Destination")) {
                TextField(String(localized: "sshPresets.form.destinationPlaceholder", defaultValue: "user@host"), text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            LabeledField(String(localized: "sshPresets.form.port", defaultValue: "Port")) {
                TextField(String(localized: "sshPresets.form.portPlaceholder", defaultValue: "22"), text: $portString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            LabeledField(String(localized: "sshPresets.form.identityFile", defaultValue: "Identity File")) {
                TextField(String(localized: "sshPresets.form.identityFilePlaceholder", defaultValue: "~/.ssh/id_rsa"), text: $identityFile)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            LabeledField(String(localized: "sshPresets.form.sshOptions", defaultValue: "SSH Options")) {
                TextField(String(localized: "sshPresets.form.sshOptionsPlaceholder", defaultValue: "-A -C"), text: $sshOptionsString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            LabeledField(String(localized: "sshPresets.form.workspaceName", defaultValue: "Workspace Name")) {
                TextField(String(localized: "sshPresets.form.workspaceNamePlaceholder", defaultValue: "Optional"), text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
        }
    }

    private func populateFromPreset() {
        guard let preset else { return }
        name = preset.name
        destination = preset.destination
        portString = preset.port.map(String.init) ?? ""
        identityFile = preset.identityFile ?? ""
        sshOptionsString = preset.sshOptions.joined(separator: " ")
        workspaceName = preset.workspaceName ?? ""
    }

    private func saveAndDismiss() {
        let trimmedDest = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmedDest.isEmpty else { return }

        let port = Int(portString.trimmingCharacters(in: .whitespaces))
        let identity = identityFile.trimmingCharacters(in: .whitespaces)
        let opts = sshOptionsString.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let wsName = workspaceName.trimmingCharacters(in: .whitespaces)

        let updated = SSHPreset(
            id: preset?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            destination: trimmedDest,
            port: port,
            identityFile: identity.isEmpty ? nil : identity,
            sshOptions: opts,
            workspaceName: wsName.isEmpty ? nil : wsName
        )

        if isEditing {
            store.update(updated)
        } else {
            store.add(updated)
        }
        onDone()
    }
}

// MARK: - Labeled field helper

private struct LabeledField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            content
        }
    }
}
