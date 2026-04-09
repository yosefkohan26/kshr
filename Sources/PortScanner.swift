import Foundation

/// Batched port scanner that replaces per-shell `ps + lsof` scanning.
///
/// Each shell sends a lightweight `report_tty` + `ports_kick` over the socket.
/// PortScanner coalesces kicks across all panels, then runs a single
/// `ps -t <ttys>` + `lsof -p <pids>` covering every panel that needs scanning.
///
/// Kick → coalesce → burst flow:
/// 1. `kick()` adds panel to `pendingKicks` set
/// 2. If no burst is active, starts a 200ms coalesce timer
/// 3. Coalesce fires → snapshots pending set → starts burst of 6 scans
/// 4. New kicks during burst merge into the active burst
/// 5. After last scan, if new kicks arrived, start a new coalesce cycle
final class PortScanner: @unchecked Sendable {
    static let shared = PortScanner()

    /// Callback delivers `(workspaceId, panelId, ports)` on the main actor.
    var onPortsUpdated: (@MainActor (_ workspaceId: UUID, _ panelId: UUID, _ ports: [Int]) -> Void)?
    /// Callback delivers workspace-scoped ports owned by tracked agents.
    var onAgentPortsUpdated: (@MainActor (_ workspaceId: UUID, _ ports: [Int]) -> Void)?
    /// Provider returns tracked agent root PIDs for the given workspaces.
    var agentPIDsProvider: (@MainActor (_ workspaceIds: Set<UUID>) -> [UUID: Set<Int>])?

    // MARK: - State (all guarded by `queue`)

    private let queue = DispatchQueue(label: "com.kshr.port-scanner", qos: .utility)

    /// TTY name per (workspace, panel).
    private var ttyNames: [PanelKey: String] = [:]

    /// Monotonic revision per workspace for tracked agent PID changes.
    private var agentRevisionByWorkspace: [UUID: UInt64] = [:]

    /// Workspaces with active agent PID tracking that need background rescans.
    private var trackedAgentWorkspaces: Set<UUID> = []

    /// Panels that requested a scan since the last coalesce snapshot.
    private var pendingKicks: Set<PanelKey> = []

    /// Whether a burst sequence is currently running.
    private var burstActive = false

    /// When true, all timers and scans are paused. Set via `suspend()` / `resume()`.
    private var isSuspended = false

    /// Coalesce timer (200ms after first kick).
    private var coalesceTimer: DispatchSourceTimer?

    /// Periodic timer for agent-owned process trees that aren't attached to a TTY.
    private var agentScanTimer: DispatchSourceTimer?

    /// Burst scan offsets in seconds from the start of the burst.
    /// Each scan fires at this absolute offset; the recursive scheduler
    /// converts to relative delays between consecutive scans.
    private static let burstOffsets: [Double] = [0.5, 1.5, 3, 5, 7.5, 10]

    /// Maximum consecutive unchanged burst scans before stopping early.
    private static let maxUnchangedBurstScans = 2

    /// Agent rescan backoff tiers (seconds). After each stable scan,
    /// the interval advances to the next tier until the max.
    private static let agentBackoffTiers: [TimeInterval] = [2, 5, 15, 30]

    /// Current backoff tier index for agent scanning.
    private var agentBackoffIndex = 0

    /// Panels that are part of the current active burst (dirty panels).
    private var burstDirtyPanels: Set<PanelKey> = []

    /// Counter of consecutive burst scans with no port changes.
    private var burstUnchangedCount = 0

    /// Last known port results per panel, used to detect changes during burst.
    private var lastPanelPorts: [PanelKey: [Int]] = [:]

    /// Last known agent ports per workspace, used to detect changes for backoff.
    private var lastAgentPorts: [UUID: [Int]] = [:]

    /// Cached process tree (pid -> parent pid) from `ps -ax`.
    /// Invalidated when agent PIDs change or on explicit refresh.
    private var cachedProcessTree: [Int: Int]?
    /// The agent root PIDs that were used to populate the cache.
    private var cachedAgentRootPIDs: Set<Int> = []

    // MARK: - Public API

    struct PanelKey: Hashable, Sendable {
        let workspaceId: UUID
        let panelId: UUID
    }

    func registerTTY(workspaceId: UUID, panelId: UUID, ttyName: String) {
        queue.async { [self] in
            let key = PanelKey(workspaceId: workspaceId, panelId: panelId)
            guard ttyNames[key] != ttyName else { return }
            ttyNames[key] = ttyName
        }
    }

    func unregisterPanel(workspaceId: UUID, panelId: UUID) {
        queue.async { [self] in
            let key = PanelKey(workspaceId: workspaceId, panelId: panelId)
            ttyNames.removeValue(forKey: key)
            pendingKicks.remove(key)
            burstDirtyPanels.remove(key)
            lastPanelPorts.removeValue(forKey: key)
        }
    }

    func kick(workspaceId: UUID, panelId: UUID) {
        queue.async { [self] in
            let key = PanelKey(workspaceId: workspaceId, panelId: panelId)
            guard ttyNames[key] != nil else { return }
            pendingKicks.insert(key)

            guard !isSuspended else { return }
            if !burstActive {
                startCoalesce()
            }
            // If burst is active, the next scan iteration will pick up the new kick.
        }
    }

    /// Pause all scanning timers. Pending kicks are preserved and will be
    /// processed when `resume()` is called. Safe to call from any thread.
    func suspend() {
        queue.async { [self] in
            guard !isSuspended else { return }
            isSuspended = true

            coalesceTimer?.cancel()
            coalesceTimer = nil
            burstActive = false

            agentScanTimer?.cancel()
            agentScanTimer = nil
        }
    }

    /// Resume scanning after a `suspend()`. If kicks accumulated while suspended,
    /// a coalesce cycle starts immediately. Safe to call from any thread.
    func resume() {
        queue.async { [self] in
            guard isSuspended else { return }
            isSuspended = false

            // Restart agent scan timer if there are tracked workspaces.
            if !trackedAgentWorkspaces.isEmpty {
                updateAgentScanTimerLocked()
            }

            // Drain any kicks that accumulated while suspended.
            if !pendingKicks.isEmpty {
                startCoalesce()
            }
        }
    }

    func refreshAgentPorts(workspaceId: UUID, agentPIDs: Set<Int>) {
        queue.async { [self] in
            refreshAgentPortsLocked(workspaceId: workspaceId, agentPIDs: agentPIDs)
        }
    }

    // MARK: - Coalesce + Burst

    private func startCoalesce() {
        // Already on `queue`.
        guard !isSuspended else { return }
        coalesceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2)
        timer.setEventHandler { [weak self] in
            self?.coalesceTimerFired()
        }
        coalesceTimer = timer
        timer.resume()
    }

    private func coalesceTimerFired() {
        // Already on `queue`.
        coalesceTimer?.cancel()
        coalesceTimer = nil

        guard !pendingKicks.isEmpty else { return }
        burstActive = true
        burstDirtyPanels = pendingKicks
        burstUnchangedCount = 0
        runBurst(index: 0)
    }

    private func runBurst(index: Int, burstStart: DispatchTime? = nil) {
        // Already on `queue`.

        // Stop early if results have been stable for enough consecutive scans.
        if burstUnchangedCount >= Self.maxUnchangedBurstScans {
            burstActive = false
            burstDirtyPanels.removeAll()
            if !pendingKicks.isEmpty {
                startCoalesce()
            }
            return
        }

        guard index < Self.burstOffsets.count else {
            burstActive = false
            burstDirtyPanels.removeAll()
            // If new kicks arrived during the burst, start a new coalesce cycle.
            if !pendingKicks.isEmpty {
                startCoalesce()
            }
            return
        }

        // Merge any new kicks that arrived since the burst started.
        if !pendingKicks.isEmpty {
            burstDirtyPanels.formUnion(pendingKicks)
            // Reset unchanged counter since new panels were added.
            burstUnchangedCount = 0
        }

        let start = burstStart ?? .now()
        let deadline = start + Self.burstOffsets[index]
        queue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self else { return }
            guard !self.isSuspended else {
                self.burstActive = false
                return
            }
            self.runScan()
            self.runBurst(index: index + 1, burstStart: start)
        }
    }

    // MARK: - Scan

    private func runScan() {
        // Already on `queue`. Only scan panels that are dirty (kicked).
        var panelSnapshot: [PanelKey: String] = [:]
        for key in burstDirtyPanels {
            if let tty = ttyNames[key] {
                panelSnapshot[key] = tty
            }
        }

        guard !panelSnapshot.isEmpty else {
            pendingKicks.removeAll()
            return
        }

        // Clear pending kicks — they're accounted for in this scan.
        pendingKicks.removeAll()

        let workspaceIds = Set(panelSnapshot.keys.map(\.workspaceId))
        let agentRevisions = agentRevisionSnapshot(for: workspaceIds)
        guard let agentPIDsProvider, !workspaceIds.isEmpty else {
            finishScan(
                panelSnapshot: panelSnapshot,
                agentPIDsByWorkspace: [:],
                agentRevisions: agentRevisions
            )
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let agentPIDsByWorkspace = await MainActor.run {
                agentPIDsProvider(workspaceIds)
            }
            self.queue.async { [weak self] in
                self?.finishScan(
                    panelSnapshot: panelSnapshot,
                    agentPIDsByWorkspace: agentPIDsByWorkspace,
                    agentRevisions: agentRevisions
                )
            }
        }
    }

    private func finishScan(
        panelSnapshot: [PanelKey: String],
        agentPIDsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        // Already on `queue`.
        let workspaceIds = Set(panelSnapshot.keys.map(\.workspaceId))

        // Build TTY set (deduplicated).
        let uniqueTTYs = Set(panelSnapshot.values)
        let ttyList = uniqueTTYs.joined(separator: ",")

        // 1. ps -t tty1,tty2,... -o pid=,tty=
        let pidToTTY = ttyList.isEmpty ? [:] : runPS(ttyList: ttyList)
        let agentPidToWorkspaces = expandAgentProcessTree(agentPIDsByWorkspace: agentPIDsByWorkspace)

        let allPids = Set(pidToTTY.keys).union(agentPidToWorkspaces.keys)
        guard !allPids.isEmpty else {
            let panelResults = panelSnapshot.map { ($0.key, [Int]()) }
            deliverResults(
                panelResults,
                workspaceIds: workspaceIds,
                agentPortsByWorkspace: [:],
                agentRevisions: agentRevisions
            )
            return
        }

        // 2. lsof -nP -a -p <all_pids> -iTCP -sTCP:LISTEN -F pn
        let pidsCsv = allPids.sorted().map(String.init).joined(separator: ",")
        let pidToPorts = runLsof(pidsCsv: pidsCsv)

        // 3. Join: PID→TTY + PID→ports → TTY→ports
        var portsByTTY: [String: Set<Int>] = [:]
        for (pid, ports) in pidToPorts {
            guard let tty = pidToTTY[pid] else { continue }
            portsByTTY[tty, default: []].formUnion(ports)
        }

        var agentPortsByWorkspace: [UUID: Set<Int>] = [:]
        for (pid, ports) in pidToPorts {
            guard let workspaceIdsForPid = agentPidToWorkspaces[pid] else { continue }
            for workspaceId in workspaceIdsForPid {
                agentPortsByWorkspace[workspaceId, default: []].formUnion(ports)
            }
        }

        // 4. Map to per-panel port lists.
        var results: [(PanelKey, [Int])] = []
        for (key, tty) in panelSnapshot {
            let ports = portsByTTY[tty].map { Array($0).sorted() } ?? []
            results.append((key, ports))
        }

        deliverResults(
            results,
            workspaceIds: workspaceIds,
            agentPortsByWorkspace: agentPortsByWorkspace,
            agentRevisions: agentRevisions
        )
    }

    private func refreshAgentPortsLocked(workspaceId: UUID, agentPIDs: Set<Int>) {
        let agentRevision = nextAgentRevision(for: workspaceId)
        let normalizedPIDs = Set(agentPIDs.filter { $0 > 0 })
        if normalizedPIDs.isEmpty {
            trackedAgentWorkspaces.remove(workspaceId)
        } else {
            trackedAgentWorkspaces.insert(workspaceId)
        }

        // PID set changed — reset backoff and invalidate process tree cache.
        agentBackoffIndex = 0
        cachedProcessTree = nil
        cachedAgentRootPIDs.removeAll()
        currentScanIsPeriodicAgent = false
        updateAgentScanTimerLocked()

        scanAgentPorts(
            workspaceIds: [workspaceId],
            agentPIDsByWorkspace: normalizedPIDs.isEmpty ? [:] : [workspaceId: normalizedPIDs],
            agentRevisions: [workspaceId: agentRevision]
        )
    }

    private func updateAgentScanTimerLocked() {
        guard !trackedAgentWorkspaces.isEmpty else {
            agentScanTimer?.cancel()
            agentScanTimer = nil
            agentBackoffIndex = 0
            return
        }
        guard !isSuspended else { return }
        // Always reschedule with current backoff interval (cancel existing first).
        agentScanTimer?.cancel()
        agentScanTimer = nil

        let interval = Self.agentBackoffTiers[agentBackoffIndex]
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            self?.runTrackedAgentScan()
        }
        agentScanTimer = timer
        timer.resume()
    }

    private func runTrackedAgentScan() {
        currentScanIsPeriodicAgent = true
        let workspaceIds = trackedAgentWorkspaces
        guard !workspaceIds.isEmpty else {
            updateAgentScanTimerLocked()
            return
        }

        let agentRevisions = agentRevisionSnapshot(for: workspaceIds)
        guard let agentPIDsProvider else {
            trackedAgentWorkspaces.removeAll()
            updateAgentScanTimerLocked()
            deliverAgentResults(
                workspaceIds: workspaceIds,
                agentPortsByWorkspace: [:],
                agentRevisions: agentRevisions
            )
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let agentPIDsByWorkspace = await MainActor.run {
                agentPIDsProvider(workspaceIds)
            }
            self.queue.async { [weak self] in
                self?.finishTrackedAgentScan(
                    workspaceIds: workspaceIds,
                    agentPIDsByWorkspace: agentPIDsByWorkspace,
                    agentRevisions: agentRevisions
                )
            }
        }
    }

    private func finishTrackedAgentScan(
        workspaceIds: Set<UUID>,
        agentPIDsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        let normalizedPIDsByWorkspace = agentPIDsByWorkspace.reduce(into: [UUID: Set<Int>]()) { partial, item in
            let valid = Set(item.value.filter { $0 > 0 })
            guard !valid.isEmpty else { return }
            partial[item.key] = valid
        }
        let inactiveWorkspaceIds = workspaceIds.subtracting(normalizedPIDsByWorkspace.keys)
        if !inactiveWorkspaceIds.isEmpty {
            trackedAgentWorkspaces.subtract(inactiveWorkspaceIds)
            updateAgentScanTimerLocked()
        }

        scanAgentPorts(
            workspaceIds: workspaceIds,
            agentPIDsByWorkspace: normalizedPIDsByWorkspace,
            agentRevisions: agentRevisions
        )
    }

    /// Tracks whether the most recent agent scan was triggered by the periodic
    /// timer (as opposed to an explicit `refreshAgentPorts` call), so we know
    /// whether to advance the backoff tier.
    private var currentScanIsPeriodicAgent = false

    private func scanAgentPorts(
        workspaceIds: Set<UUID>,
        agentPIDsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        guard !workspaceIds.isEmpty else { return }

        let agentPidToWorkspaces = expandAgentProcessTree(agentPIDsByWorkspace: agentPIDsByWorkspace)
        guard !agentPidToWorkspaces.isEmpty else {
            deliverAgentResultsWithBackoff(
                workspaceIds: workspaceIds,
                agentPortsByWorkspace: [:],
                agentRevisions: agentRevisions
            )
            return
        }

        let pidsCsv = agentPidToWorkspaces.keys.sorted().map(String.init).joined(separator: ",")
        let pidToPorts = runLsof(pidsCsv: pidsCsv)
        var agentPortsByWorkspace: [UUID: Set<Int>] = [:]
        for (pid, ports) in pidToPorts {
            guard let workspaceIdsForPid = agentPidToWorkspaces[pid] else { continue }
            for targetWorkspaceId in workspaceIdsForPid {
                agentPortsByWorkspace[targetWorkspaceId, default: []].formUnion(ports)
            }
        }

        deliverAgentResultsWithBackoff(
            workspaceIds: workspaceIds,
            agentPortsByWorkspace: agentPortsByWorkspace,
            agentRevisions: agentRevisions
        )
    }

    /// Delivers agent results and adjusts backoff for periodic scans.
    private func deliverAgentResultsWithBackoff(
        workspaceIds: Set<UUID>,
        agentPortsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        // Check if ports changed for backoff calculation.
        if currentScanIsPeriodicAgent {
            var anyAgentChanged = false
            for workspaceId in workspaceIds {
                let ports = Array(agentPortsByWorkspace[workspaceId] ?? []).sorted()
                if lastAgentPorts[workspaceId] != ports {
                    lastAgentPorts[workspaceId] = ports
                    anyAgentChanged = true
                }
            }

            if anyAgentChanged {
                // Ports changed — reset to fastest polling.
                agentBackoffIndex = 0
                // Invalidate process tree cache since the landscape changed.
                cachedProcessTree = nil
                cachedAgentRootPIDs.removeAll()
            } else {
                // Stable — advance backoff tier.
                agentBackoffIndex = min(
                    agentBackoffIndex + 1,
                    Self.agentBackoffTiers.count - 1
                )
            }
            // Schedule next periodic scan with updated interval.
            updateAgentScanTimerLocked()
        }

        deliverAgentResults(
            workspaceIds: workspaceIds,
            agentPortsByWorkspace: agentPortsByWorkspace,
            agentRevisions: agentRevisions
        )
    }

    private func deliverResults(
        _ panelResults: [(PanelKey, [Int])],
        workspaceIds: Set<UUID>,
        agentPortsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        // Track whether any panel's ports changed to support early burst termination.
        var anyChanged = false
        for (key, ports) in panelResults {
            if lastPanelPorts[key] != ports {
                lastPanelPorts[key] = ports
                anyChanged = true
            }
        }

        if anyChanged {
            burstUnchangedCount = 0
        } else {
            burstUnchangedCount += 1
        }

        let panelCallback = onPortsUpdated
        if let panelCallback {
            Task { @MainActor in
                for (key, ports) in panelResults {
                    panelCallback(key.workspaceId, key.panelId, ports)
                }
            }
        }
        deliverAgentResults(
            workspaceIds: workspaceIds,
            agentPortsByWorkspace: agentPortsByWorkspace,
            agentRevisions: agentRevisions
        )
    }

    private func deliverAgentResults(
        workspaceIds: Set<UUID>,
        agentPortsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) {
        guard let agentCallback = onAgentPortsUpdated else { return }
        Task { [weak self] in
            guard let self else { return }
            let validatedResults = await self.validatedAgentResults(
                workspaceIds: workspaceIds,
                agentPortsByWorkspace: agentPortsByWorkspace,
                agentRevisions: agentRevisions
            )
            guard !validatedResults.isEmpty else { return }
            await MainActor.run {
                for (workspaceId, ports) in validatedResults {
                    agentCallback(workspaceId, ports)
                }
            }
        }
    }

    private func validatedAgentResults(
        workspaceIds: Set<UUID>,
        agentPortsByWorkspace: [UUID: Set<Int>],
        agentRevisions: [UUID: UInt64]
    ) async -> [(UUID, [Int])] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var results: [(UUID, [Int])] = []
                for workspaceId in workspaceIds.sorted(by: { $0.uuidString < $1.uuidString }) {
                    let currentRevision = agentRevisionByWorkspace[workspaceId, default: 0]
                    let expectedRevision = agentRevisions[workspaceId, default: 0]
                    guard currentRevision == expectedRevision else { continue }
                    let ports = Array(agentPortsByWorkspace[workspaceId] ?? []).sorted()
                    results.append((workspaceId, ports))
                }
                continuation.resume(returning: results)
            }
        }
    }

    private func agentRevisionSnapshot(for workspaceIds: Set<UUID>) -> [UUID: UInt64] {
        workspaceIds.reduce(into: [UUID: UInt64]()) { partial, workspaceId in
            partial[workspaceId] = agentRevisionByWorkspace[workspaceId, default: 0]
        }
    }

    private func nextAgentRevision(for workspaceId: UUID) -> UInt64 {
        let nextRevision = agentRevisionByWorkspace[workspaceId, default: 0] &+ 1
        agentRevisionByWorkspace[workspaceId] = nextRevision
        return nextRevision
    }

    // MARK: - Process helpers

    private func expandAgentProcessTree(agentPIDsByWorkspace: [UUID: Set<Int>]) -> [Int: Set<UUID>] {
        let normalizedRoots = agentPIDsByWorkspace.reduce(into: [UUID: Set<Int>]()) { partial, item in
            let valid = Set(item.value.filter { $0 > 0 })
            guard !valid.isEmpty else { return }
            partial[item.key] = valid
        }
        guard !normalizedRoots.isEmpty else { return [:] }

        // Collect all root PIDs to check if the cache is still valid.
        let allRootPIDs = normalizedRoots.values.reduce(into: Set<Int>()) { $0.formUnion($1) }

        var pidToWorkspaces: [Int: Set<UUID>] = [:]
        var queue: [(pid: Int, workspaceId: UUID)] = []
        for (workspaceId, roots) in normalizedRoots {
            for pid in roots {
                if pidToWorkspaces[pid, default: []].insert(workspaceId).inserted {
                    queue.append((pid, workspaceId))
                }
            }
        }

        // Use cached process tree if root PIDs haven't changed.
        let parentByPid: [Int: Int]
        if let cached = cachedProcessTree, cachedAgentRootPIDs == allRootPIDs {
            parentByPid = cached
        } else {
            parentByPid = runAllProcesses()
            cachedProcessTree = parentByPid
            cachedAgentRootPIDs = allRootPIDs
        }
        guard !parentByPid.isEmpty else { return pidToWorkspaces }

        var childrenByParent: [Int: [Int]] = [:]
        for (pid, parentPid) in parentByPid {
            childrenByParent[parentPid, default: []].append(pid)
        }

        var index = 0
        while index < queue.count {
            let (pid, workspaceId) = queue[index]
            index += 1

            for childPid in childrenByParent[pid] ?? [] {
                if pidToWorkspaces[childPid, default: []].insert(workspaceId).inserted {
                    queue.append((childPid, workspaceId))
                }
            }
        }

        return pidToWorkspaces
    }

    private func runPS(ttyList: String) -> [Int: String] {
        // `ps -t tty1,tty2,... -o pid=,tty=` — targeted scan, much cheaper than -ax.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-t", ttyList, "-o", "pid=,tty="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var mapping: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int(parts[0]) else { continue }
            mapping[pid] = String(parts[1])
        }
        return mapping
    }

    private func runAllProcesses() -> [Int: Int] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "pid=,ppid="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var mapping: [Int: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int(parts[0]),
                  let parentPid = Int(parts[1]) else { continue }
            mapping[pid] = parentPid
        }
        return mapping
    }

    private func runLsof(pidsCsv: String) -> [Int: Set<Int>] {
        // `lsof -nP -a -p <pids> -iTCP -sTCP:LISTEN -F pn`
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", pidsCsv, "-iTCP", "-sTCP:LISTEN", "-Fpn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        // Parse lsof -F output: lines starting with 'p' = PID, 'n' = name (host:port).
        var result: [Int: Set<Int>] = [:]
        var currentPid: Int?
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            switch first {
            case "p":
                currentPid = Int(line.dropFirst())
            case "n":
                guard let pid = currentPid else { continue }
                var name = String(line.dropFirst())
                // Strip remote endpoint if present.
                if let arrowIdx = name.range(of: "->") {
                    name = String(name[..<arrowIdx.lowerBound])
                }
                // Port is after the last colon.
                if let colonIdx = name.lastIndex(of: ":") {
                    let portStr = name[name.index(after: colonIdx)...]
                    // Strip anything non-numeric.
                    let cleaned = portStr.prefix(while: \.isNumber)
                    if let port = Int(cleaned), port > 0, port <= 65535 {
                        result[pid, default: []].insert(port)
                    }
                }
            default:
                break
            }
        }
        return result
    }
}
