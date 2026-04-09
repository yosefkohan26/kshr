import Foundation
import SwiftUI

// MARK: - Model

struct SSHPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var destination: String  // user@host
    var port: Int?
    var identityFile: String?
    var sshOptions: [String]
    var workspaceName: String?

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        port: Int? = nil,
        identityFile: String? = nil,
        sshOptions: [String] = [],
        workspaceName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.port = port
        self.identityFile = identityFile
        self.sshOptions = sshOptions
        self.workspaceName = workspaceName
    }

    /// Display label: name if set, otherwise destination with port.
    var displayLabel: String {
        if !name.isEmpty { return name }
        if let port { return "\(destination):\(port)" }
        return destination
    }
}

// MARK: - Store

@MainActor
final class SSHPresetStore: ObservableObject {
    static let shared = SSHPresetStore()

    @Published private(set) var presets: [SSHPreset] = []

    private static let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/kshr", isDirectory: true)
    }()

    private static let fileURL: URL = {
        configDir.appendingPathComponent("ssh-presets.json")
    }()

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ preset: SSHPreset) {
        presets.append(preset)
        save()
    }

    func update(_ preset: SSHPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        save()
    }

    func delete(_ preset: SSHPreset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            presets = try JSONDecoder().decode([SSHPreset].self, from: data)
        } catch {
            #if DEBUG
            print("[SSHPresetStore] load error: \(error)")
            #endif
        }
    }

    private func save() {
        let url = Self.fileURL
        do {
            try FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[SSHPresetStore] save error: \(error)")
            #endif
        }
    }

    // MARK: - Connect

    /// Launch `kshr ssh` for the given preset using the bundled CLI.
    func connect(_ preset: SSHPreset) {
        guard let cliURL = Bundle.main.resourceURL?.appendingPathComponent("bin/kshr", isDirectory: false),
              FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            connectWithPath("/usr/local/bin/kshr", preset: preset)
            return
        }
        connectWithPath(cliURL.path, preset: preset)
    }

    private func connectWithPath(_ cliPath: String, preset: SSHPreset) {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            #if DEBUG
            print("[SSHPresetStore] CLI not found at \(cliPath)")
            #endif
            return
        }

        var args = ["ssh"]
        if let port = preset.port {
            args += ["--port", String(port)]
        }
        if let identity = preset.identityFile, !identity.isEmpty {
            args += ["--identity", identity]
        }
        let wsName = preset.workspaceName ?? preset.name
        if !wsName.isEmpty {
            args += ["--name", wsName]
        }
        for opt in preset.sshOptions {
            args += ["--ssh-option", opt]
        }
        args.append(preset.destination)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            #if DEBUG
            print("[SSHPresetStore] launch error: \(error)")
            #endif
        }
    }
}
