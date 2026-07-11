import Foundation

@MainActor
final class UsageStore: NSObject {
    private let providers: [any UsageProvider]
    private let cacheURL: URL
    private var timer: Timer?
    private var refreshInProgress = false

    private(set) var states: [ProviderID: ProviderState]
    var onChange: (() -> Void)?

    init(
        providers: [any UsageProvider] = [ClaudeProvider(), CodexProvider(), GrokProvider()],
        cacheURL: URL = UsageStore.defaultCacheURL
    ) {
        self.providers = providers
        self.cacheURL = cacheURL
        self.states = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, ProviderState()) })
    }

    func start() {
        loadCache()
        timer = Timer.scheduledTimer(
            timeInterval: 300,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        Task { await refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true

        for provider in providers {
            states[provider.id, default: ProviderState()].isRefreshing = true
        }
        onChange?()

        let results = await withTaskGroup(
            of: (ProviderID, Result<ProviderSnapshot, ProviderError>).self,
            returning: [(ProviderID, Result<ProviderSnapshot, ProviderError>)].self
        ) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.fetch()))
                    } catch let error as ProviderError {
                        return (provider.id, .failure(error))
                    } catch {
                        return (provider.id, .failure(.processFailed(error.localizedDescription)))
                    }
                }
            }

            var values: [(ProviderID, Result<ProviderSnapshot, ProviderError>)] = []
            for await value in group { values.append(value) }
            return values
        }

        for (id, result) in results {
            switch result {
            case .success(let snapshot):
                states[id] = ProviderState(snapshot: snapshot)
            case .failure(let error):
                var state = states[id, default: ProviderState()]
                state.errorMessage = error.localizedDescription
                state.isRefreshing = false
                state.isStale = state.snapshot != nil
                states[id] = state
            }
        }

        refreshInProgress = false
        saveCache()
        onChange?()
    }

    @objc private func refreshTimerFired() {
        Task { await refresh() }
    }

    private func loadCache() {
        guard
            let data = try? Data(contentsOf: cacheURL),
            let snapshots = try? JSONDecoder.quotaBar.decode([ProviderSnapshot].self, from: data)
        else { return }

        for snapshot in snapshots {
            states[snapshot.provider] = ProviderState(snapshot: snapshot, isStale: true)
        }
        onChange?()
    }

    private func saveCache() {
        let snapshots = states.values.compactMap(\.snapshot)
        guard let data = try? JSONEncoder.quotaBar.encode(snapshots) else { return }

        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "QuotaBar", directoryHint: .isDirectory)
            .appending(path: "snapshots.json")
    }
}

private extension JSONEncoder {
    static var quotaBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var quotaBar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

