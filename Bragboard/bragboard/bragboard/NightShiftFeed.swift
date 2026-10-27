//
//  NightShiftFeed.swift
//  bragboard
//
//  Night Shift data for the TV: the feed's JSON shape, sample data, and a
//  store that polls the feed and keeps the last good value.
//
//  🔐 The read-only TV key lives in Config.plist (NightShiftTVKey) only —
//     never in code, CloudKit or logs. People appear as initials only.
//

import Foundation
import Observation

// MARK: - Feed Shape

/// Mirrors `GET /v1/night-shift/tv` exactly.
struct NightShiftSnapshot: Codable, Equatable {
    enum Status: String, Codable {
        case none, scheduled, live, ended, cancelled
    }

    struct Session: Codable, Equatable {
        let date: String
        let startsAt: Date
        let endsAt: Date
    }

    struct Standup: Codable, Equatable {
        let at: Date?
        let now: Bool
    }

    struct Pizza: Codable, Equatable {
        let at: Date?
        let arrived: Bool
    }

    struct Person: Codable, Equatable {
        let initials: String
        let remote: Bool
    }

    struct Here: Codable, Equatable {
        let total: Int
        let onSite: Int
        let remote: Int
        let people: [Person]
    }

    struct Activity: Codable, Equatable {
        let initials: String
        let text: String
        let kind: String
        let at: Date
    }

    let status: Status
    // Optional so a "none" night can leave them out.
    let session: Session?
    let standup: Standup?
    let pizza: Pizza?
    let here: Here?
    let activity: [Activity]?
    let updatedAt: Date

    /// Decodes ISO times with or without fractional seconds.
    static func decode(_ data: Data) throws -> NightShiftSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 time")
        }
        return try decoder.decode(NightShiftSnapshot.self, from: data)
    }
}

// MARK: - What the TV Shows

extension NightShiftSnapshot {
    /// The page joins the slideshow only while a session is live and not yet
    /// over, so a cached "live" snapshot can't outlive the evening.
    func showsPage(now: Date = Date()) -> Bool {
        guard status == .live, let session else { return false }
        return now < session.endsAt
    }

    /// Finished public tasks, newest first.
    var finishedTasks: [Activity] {
        (activity ?? [])
            .filter { $0.kind == "finished" }
            .sorted { $0.at > $1.at }
    }

    /// The dashboard card shows on the evening only: from 1 hour before the
    /// session starts until it ends. The rest of the day the grid is as normal.
    func showsCard(now: Date = Date()) -> Bool {
        guard let session, [.scheduled, .live, .cancelled].contains(status) else { return false }
        return now >= session.startsAt.addingTimeInterval(-60 * 60) && now < session.endsAt
    }

    /// The dashboard card's title, or nil to hide the card.
    func cardTitle(now: Date = Date(), calendar: Calendar = .current) -> String? {
        let day = session.map { NightShiftFormat.day($0.startsAt, now: now, calendar: calendar) } ?? "tonight"
        switch status {
        case .live: return "Night Shift tonight"
        case .scheduled: return "Night Shift \(day)"
        case .cancelled: return "Night Shift cancelled \(day)"
        case .none, .ended: return nil
        }
    }

    /// Beside the big count on the card: "here now, 9 remote".
    var hereLabel: String {
        let remote = here?.remote ?? 0
        return remote > 0 ? "here now, \(remote) remote" : "here now"
    }

    /// Under the big count on the page: "37 on site, 9 remote".
    var hereBreakdown: String? {
        here.map { "\($0.onSite) on site, \($0.remote) remote" }
    }

    /// "Starts at 6 pm" on a scheduled night's card.
    func startsLine(calendar: Calendar = .current) -> String? {
        guard status == .scheduled, let session else { return nil }
        return "Starts at \(NightShiftFormat.time(session.startsAt, calendar: calendar))"
    }

    /// "Night Shift, Tuesday 27 October, 6:00 pm to 10:00 pm"
    func sessionLine(calendar: Calendar = .current) -> String? {
        guard let session else { return nil }
        let day = NightShiftFormat.longDay(session.startsAt, calendar: calendar)
        let from = NightShiftFormat.clock(session.startsAt, calendar: calendar)
        let to = NightShiftFormat.clock(session.endsAt, calendar: calendar)
        return "Night Shift, \(day), \(from) to \(to)"
    }

    /// Page wording: "Now", "At 7:30 pm" or "Was at 6:15 pm".
    func standupDetail(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let standup else { return nil }
        if standup.now { return "Now" }
        guard let at = standup.at else { return nil }
        let time = NightShiftFormat.time(at, calendar: calendar)
        return at > now ? "At \(time)" : "Was at \(time)"
    }

    /// Card wording: "Stand-up now", "Stand-up at 7:30 pm" or "Stand-up was at 6:15 pm".
    func standupLine(now: Date = Date(), calendar: Calendar = .current) -> String? {
        standupDetail(now: now, calendar: calendar).map { "Stand-up " + $0.prefix(1).lowercased() + $0.dropFirst() }
    }

    /// "11:59" under an hour, "1 hr 5 min" beyond; nil once pizza is due or here.
    func pizzaCountdown(now: Date = Date()) -> String? {
        guard let pizza, !pizza.arrived, let at = pizza.at else { return nil }
        let seconds = Int(at.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return nil }
        if seconds < 3_600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        let minutes = (seconds + 59) / 60
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    /// Under the countdown on the page: "until 7:30 pm".
    func pizzaDetail(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard pizzaCountdown(now: now) != nil, let at = pizza?.at else { return nil }
        return "until \(NightShiftFormat.time(at, calendar: calendar))"
    }

    /// When there is no countdown: "Pizza's here" or "Pizza any minute".
    func pizzaLine(now: Date = Date()) -> String? {
        guard let pizza else { return nil }
        if pizza.arrived { return "Pizza's here" }
        guard pizza.at != nil else { return nil }
        return pizzaCountdown(now: now).map { "Pizza in \($0)" } ?? "Pizza any minute"
    }
}

enum NightShiftFormat {
    /// "6 pm", or "7:30 pm" when the minutes matter.
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a", calendar).string(from: date)
    }

    /// Always with minutes: "6:00 pm".
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("h:mm a", calendar).string(from: date)
    }

    /// "Tuesday 27 October"
    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("EEEE d MMMM", calendar).string(from: date)
    }

    /// "tonight" for today, otherwise the weekday ("Thursday").
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "tonight" : formatter("EEEE", calendar).string(from: date)
    }

    /// "just now", "4 min ago", "2 hr ago"
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3_600) hr ago"
    }

    /// English wording with lowercase "am"/"pm", in the calendar's time zone.
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Source

enum NightShiftSource {
    case sample
    case live(URL)
}

enum NightShiftFeedError: LocalizedError {
    case missingKey
    case badStatus(Int)
    case sampleInRelease

    var errorDescription: String? {
        switch self {
        case .missingKey: "NightShiftTVKey is not set in Config.plist"
        case .badStatus(let code): "Night Shift feed returned HTTP \(code)"
        case .sampleInRelease: "Night Shift sample data is off in Release builds"
        }
    }
}

enum NightShiftFeed {
    static let liveURL = URL(string: "https://api.thefoundry.peiitalliance.com/v1/night-shift/tv")!

    /// The one line to change when the Foundry endpoint exists: `.live(liveURL)`.
    /// Merge guard: delete the #warning with it. NightShiftFeedTests fails while this is `.sample`.
    #warning("Night Shift runs on sample data. Set NightShiftFeed.source = .live(liveURL) before merging.")
    static let source: NightShiftSource = .sample

    /// Read once, so polling doesn't re-read Config.plist every time.
    private static let tvKey = AppConfig.shared.nightShiftTVKey

    static func load() async throws -> NightShiftSnapshot {
        switch source {
        case .sample:
            #if DEBUG
            return NightShiftSample.snapshot()
            #else
            // Never show sample people on the real TV.
            throw NightShiftFeedError.sampleInRelease
            #endif
        case .live(let url):
            return try await fetch(url: url, key: tvKey)
        }
    }

    static func fetch(url: URL, key: String, session: URLSession = .shared) async throws -> NightShiftSnapshot {
        guard !key.isEmpty else { throw NightShiftFeedError.missingKey }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw NightShiftFeedError.badStatus(code) }
        return try NightShiftSnapshot.decode(data)
    }
}

// MARK: - Store

/// Polls the feed. A failed fetch keeps the last good snapshot on screen.
@Observable
final class NightShiftStore {
    private(set) var snapshot: NightShiftSnapshot?
    private(set) var lastSuccess: Date?

    private let load: () async throws -> NightShiftSnapshot
    private var pollTask: Task<Void, Never>?

    /// `load` is injectable so tests can feed successes and failures.
    init(load: @escaping () async throws -> NightShiftSnapshot = NightShiftFeed.load) {
        self.load = load
    }

    /// 45 s while a session is live, otherwise every 5 minutes.
    var pollInterval: TimeInterval {
        snapshot?.status == .live ? 45 : 300
    }

    func refresh(now: Date = Date()) async {
        do {
            snapshot = try await load()
            lastSuccess = now
        } catch is CancellationError {
            // stopPolling() cancelled the fetch. Nothing failed.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            // Log only the error, never the request or the key.
            print("🌙 Night Shift fetch failed: \(error.localizedDescription)")
        }
    }

    /// Stale after three missed polls; the TV then shows a quiet "last updated" time.
    func isStale(now: Date = Date()) -> Bool {
        guard let lastSuccess else { return false }
        return now.timeIntervalSince(lastSuccess) > pollInterval * 3
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Stop once the store is gone. The sleep holds no reference to it.
                guard let wait = await self?.refreshAndWait() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func refreshAndWait() async -> TimeInterval {
        await refresh()
        return pollInterval
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Sample Data

/// A live night built around `now`, in the feed's exact shape. Initials only.
enum NightShiftSample {
    private static let initials = [
        "AK", "BT", "CM", "DL", "EW", "FN", "GH", "HP", "IR", "JS", "KB", "LC",
        "MD", "NE", "OF", "PG", "QH", "RJ", "SK", "TL", "UM", "VN", "WO", "XP",
        "YQ", "ZR", "AS", "BU", "CV", "DW", "EX", "FY", "GZ", "HA", "IB", "JC",
        "KD", "LE", "MF", "NG", "OH", "PI", "QJ", "RK", "SL", "TM",
    ]

    private static let remoteIndexes: Set<Int> = [3, 9, 14, 17, 24, 29, 31, 38, 44]

    static func snapshot(now: Date = Date(), calendar: Calendar = .current) -> NightShiftSnapshot {
        // Started on the hour, about an hour ago, like a real night.
        let startsAt = calendar.dateInterval(of: .hour, for: now.addingTimeInterval(-60 * 60))?.start
            ?? now.addingTimeInterval(-60 * 60)
        let people = initials.enumerated().map { index, value in
            NightShiftSnapshot.Person(initials: value, remote: remoteIndexes.contains(index))
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        func finished(_ initials: String, _ text: String, minutesAgo: Double) -> NightShiftSnapshot.Activity {
            .init(initials: initials, text: text, kind: "finished", at: now.addingTimeInterval(-minutesAgo * 60))
        }

        return NightShiftSnapshot(
            status: .live,
            session: .init(
                date: dayFormatter.string(from: startsAt),
                startsAt: startsAt,
                endsAt: startsAt.addingTimeInterval(4 * 60 * 60)
            ),
            standup: .init(at: startsAt.addingTimeInterval(15 * 60), now: false),
            pizza: .init(at: now.addingTimeInterval(12 * 60), arrived: false),
            here: .init(
                total: people.count,
                onSite: people.count - remoteIndexes.count,
                remote: remoteIndexes.count,
                people: people
            ),
            activity: [
                finished("TB", "Write tests for the export feature", minutesAgo: 1),
                finished("KM", "Design a logo for a bakery", minutesAgo: 2),
                finished("AV", "Answer support emails", minutesAgo: 4),
                finished("LF", "Clean up the photo archive", minutesAgo: 5),
                finished("JF", "Translate the menu into French", minutesAgo: 8),
                finished("SR", "Ship the pricing page", minutesAgo: 8.5),
            ],
            updatedAt: now
        )
    }
}
