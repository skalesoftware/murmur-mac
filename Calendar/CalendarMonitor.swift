import Foundation
import EventKit
import Observation
import AppKit

/// Watches the user's calendars and auto-starts/stops Murmur recordings
/// when events begin and end. Requires full Calendar access (macOS 14+).
@MainActor
@Observable
final class CalendarMonitor {

    // MARK: - Observable state

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "murmur.calendarAutoStart") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "murmur.calendarAutoStart")
            isEnabled ? beginPolling() : endPolling()
        }
    }
    var accessGranted = false
    /// The next upcoming event we intend to record (shown in Settings).
    var upcomingEvent: EKEvent?

    // MARK: - Internal

    weak var controller: RecordingController?

    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var startTimer: Timer?
    private var stopTimer: Timer?
    private var scheduledEventID: String?
    private var storeObserver: Any?

    // MARK: - Access

    func requestAccessIfNeeded() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .authorized {
            accessGranted = true
            if isEnabled { beginPolling() }
            return
        }
        guard status == .notDetermined else { return }
        do {
            accessGranted = try await store.requestFullAccessToEvents()
            if accessGranted && isEnabled { beginPolling() }
        } catch {
            accessGranted = false
        }
    }

    func openCalendarSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private func beginPolling() {
        guard accessGranted else { return }

        checkUpcoming()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkUpcoming() }
        }

        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkUpcoming() }
        }
    }

    private func endPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        startTimer?.invalidate(); startTimer = nil
        stopTimer?.invalidate(); stopTimer = nil
        scheduledEventID = nil
        upcomingEvent = nil
        if let obs = storeObserver { NotificationCenter.default.removeObserver(obs) }
        storeObserver = nil
    }

    // MARK: - Event matching

    private func checkUpcoming() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),   // include events that just started
            end: now.addingTimeInterval(5 * 60),      // look up to 5 min ahead
            calendars: nil
        )

        let candidates = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now.addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }

        upcomingEvent = candidates.first

        guard let event = candidates.first,
              event.eventIdentifier != scheduledEventID else { return }

        scheduledEventID = event.eventIdentifier
        let title   = event.title ?? "Meeting"
        let starts  = event.startDate!
        let ends    = event.endDate ?? starts.addingTimeInterval(3600)
        let delay   = max(0, starts.timeIntervalSinceNow)

        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let ctrl = self.controller,
                      !ctrl.isRecording, !ctrl.isBusy else { return }

                // Bring Murmur to the foreground so the user can see it recording.
                NSApp.activate(ignoringOtherApps: true)

                await ctrl.startRecording(calendarTitle: title)

                // Schedule auto-stop at event end.
                let stopDelay = max(60, ends.timeIntervalSinceNow)
                self.stopTimer?.invalidate()
                self.stopTimer = Timer.scheduledTimer(withTimeInterval: stopDelay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let ctrl = self?.controller, ctrl.isRecording else { return }
                        await ctrl.stopRecording()
                    }
                }
            }
        }
    }
}
