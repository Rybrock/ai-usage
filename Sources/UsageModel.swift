import Foundation
import Combine

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    /// Fired after every refresh so the status-bar button can redraw.
    var onUpdate: (() -> Void)?

    private var timer: Timer?

    /// The usage endpoint rate limits at roughly one call per 250s, so poll
    /// comfortably outside that window.
    private static let pollInterval: TimeInterval = 300

    /// Opening the popover refreshes, but not if we just fetched.
    private static let staleAfter: TimeInterval = 60

    /// Set when the server hands back a Retry-After; blocks fetches until then.
    private var nextAllowedFetch: Date?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Called when the popover opens — avoids burning a request on fresh data.
    func refreshIfStale() {
        guard let snapshot else { refresh(); return }
        if Date().timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter {
            refresh()
        }
    }

    /// - Parameter force: ignore the server-imposed backoff (manual refresh).
    func refresh(force: Bool = false) {
        guard !isLoading else { return }

        if !force, let next = nextAllowedFetch, Date() < next {
            return
        }

        isLoading = true

        Task { @MainActor in
            defer {
                isLoading = false
                onUpdate?()
            }
            do {
                snapshot = try await UsageService.fetch()
                errorMessage = nil
                nextAllowedFetch = nil
            } catch {
                // Keep the last good numbers on screen; surface the error above them.
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

                if let delay = (error as? UsageError)?.retryDelay {
                    nextAllowedFetch = Date().addingTimeInterval(delay)
                    scheduleRetry(after: delay + 5)
                }
            }
        }
    }

    /// After a 429 the regular poll may be minutes away; retry as soon as the
    /// server-supplied window expires so the numbers recover quickly.
    private func scheduleRetry(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.refresh()
        }
    }
}
