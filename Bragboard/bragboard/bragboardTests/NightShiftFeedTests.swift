//
//  NightShiftFeedTests.swift
//  bragboardTests
//

import Foundation
import Testing
@testable import bragboard

@MainActor
struct NightShiftFeedTests {

    /// Atlantic time, so the "6 pm" style lines don't depend on the test Mac.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Halifax")!
        return calendar
    }()

    private static func date(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    /// The agreed feed shape, with a fractional-seconds time mixed in.
    private static let liveJSON = """
    {
      "status": "live",
      "session": { "date": "2026-10-27", "startsAt": "2026-10-27T21:00:00Z", "endsAt": "2026-10-28T01:00:00Z" },
      "standup": { "at": "2026-10-27T22:30:00.000Z", "now": false },
      "pizza": { "at": null, "arrived": true },
      "here": { "total": 44, "onSite": 38, "remote": 6, "people": [ { "initials": "AK", "remote": false }, { "initials": "BT", "remote": true } ] },
      "activity": [
        { "initials": "AK", "text": "Clean up the photo archive", "kind": "finished", "at": "2026-10-27T22:10:00Z" },
        { "initials": "BT", "text": "Started on the tests", "kind": "started", "at": "2026-10-27T22:20:00Z" },
        { "initials": "CM", "text": "Fix the sign-up form", "kind": "finished", "at": "2026-10-27T22:15:00Z" }
      ],
      "updatedAt": "2026-10-27T22:16:05.123Z"
    }
    """

    // MARK: - Decoding

    @Test func decodesTheAgreedFeedShape() throws {
        let snapshot = try NightShiftSnapshot.decode(Data(Self.liveJSON.utf8))

        #expect(snapshot.status == .live)
        #expect(snapshot.session?.startsAt == Self.date("2026-10-27T21:00:00Z"))
        #expect(snapshot.standup?.at == Self.date("2026-10-27T22:30:00Z"))
        #expect(snapshot.pizza == .init(at: nil, arrived: true))
        #expect(snapshot.here?.total == 44)
        #expect(snapshot.here?.people.last == .init(initials: "BT", remote: true))
        #expect(snapshot.activity?.count == 3)
    }

    /// The feed no longer sends session.location. BragBoard decodes the session
    /// without it, and no line on the page or card shows a place.
    @Test func decodesASessionWithoutLocationAndShowsNoPlace() throws {
        let json = """
        {
          "status": "live",
          "session": { "date": "2026-10-27", "startsAt": "2026-10-27T21:00:00Z", "endsAt": "2026-10-28T01:00:00Z" },
          "standup": { "at": "2026-10-27T21:15:00Z", "now": false },
          "pizza": { "at": "2026-10-27T22:30:00Z", "arrived": false },
          "here": { "total": 2, "onSite": 1, "remote": 1, "people": [ { "initials": "AK", "remote": false }, { "initials": "BT", "remote": true } ] },
          "activity": [ { "initials": "AK", "text": "Clean up the photo archive", "kind": "finished", "at": "2026-10-27T21:55:00Z" } ],
          "updatedAt": "2026-10-27T22:00:00Z"
        }
        """
        let now = Self.date("2026-10-27T22:00:00Z") // 7 pm Atlantic
        let snapshot = try NightShiftSnapshot.decode(Data(json.utf8))

        #expect(snapshot.session == .init(
            date: "2026-10-27",
            startsAt: Self.date("2026-10-27T21:00:00Z"),
            endsAt: Self.date("2026-10-28T01:00:00Z")
        ))

        // Every line the page and card show, word for word. None names a place.
        #expect(snapshot.cardTitle(now: now, calendar: Self.calendar) == "Night Shift tonight")
        #expect(snapshot.sessionLine(calendar: Self.calendar) == "Night Shift, Tuesday 27 October, 6:00 pm to 10:00 pm")
        #expect(snapshot.startsLine(calendar: Self.calendar) == nil)
        #expect(snapshot.hereLabel == "here now, 1 remote")
        #expect(snapshot.hereBreakdown == "1 on site, 1 remote")
        #expect(snapshot.standupDetail(now: now, calendar: Self.calendar) == "Was at 6:15 pm")
        #expect(snapshot.standupLine(now: now, calendar: Self.calendar) == "Stand-up was at 6:15 pm")
        #expect(snapshot.pizzaCountdown(now: now) == "30:00")
        #expect(snapshot.pizzaDetail(now: now, calendar: Self.calendar) == "until 7:30 pm")
        #expect(snapshot.pizzaLine(now: now) == "Pizza in 30:00")
        #expect(snapshot.finishedTasks.map(\.text) == ["Clean up the photo archive"])

        // An older feed that still sends a location decodes to the same data,
        // so the place can't reach the screen either way.
        let withLocation = json.replacingOccurrences(
            of: #""endsAt": "2026-10-28T01:00:00Z" }"#,
            with: #""endsAt": "2026-10-28T01:00:00Z", "location": "2nd floor" }"#
        )
        #expect(withLocation.contains("2nd floor"))
        #expect(try NightShiftSnapshot.decode(Data(withLocation.utf8)) == snapshot)
    }

    @Test func decodesAQuietNightWithoutSessionDetails() throws {
        let json = #"{ "status": "none", "updatedAt": "2026-10-27T15:00:00Z" }"#
        let snapshot = try NightShiftSnapshot.decode(Data(json.utf8))

        #expect(snapshot.status == .none)
        #expect(snapshot.session == nil)
        #expect(snapshot.finishedTasks.isEmpty)
        #expect(snapshot.cardTitle(calendar: Self.calendar) == nil)
    }

    @Test func rejectsAnUnknownStatus() {
        let json = #"{ "status": "paused", "updatedAt": "2026-10-27T15:00:00Z" }"#
        #expect(throws: DecodingError.self) {
            try NightShiftSnapshot.decode(Data(json.utf8))
        }
    }

    @Test func sampleDataMatchesTheFeedShape() throws {
        let sample = NightShiftSample.snapshot(now: Self.date("2026-10-27T22:00:00Z"), calendar: Self.calendar)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try NightShiftSnapshot.decode(encoder.encode(sample))

        #expect(decoded == sample)
        #expect(decoded.showsPage(now: Self.date("2026-10-27T22:00:00Z")))
        #expect(decoded.here?.total == decoded.here?.people.count)
        // Initials only: two capital letters, never a name.
        #expect(decoded.here?.people.allSatisfy { $0.initials.count == 2 && $0.initials == $0.initials.uppercased() } == true)
    }

    // MARK: - Keep the Last Good Value

    @Test func keepsTheLastGoodValueWhenAFetchFails() async throws {
        let good = try NightShiftSnapshot.decode(Data(Self.liveJSON.utf8))
        var shouldFail = false
        let store = NightShiftStore {
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return good
        }
        let first = Self.date("2026-10-27T22:00:00Z")

        await store.refresh(now: first)
        #expect(store.snapshot == good)
        #expect(store.lastSuccess == first)

        shouldFail = true
        await store.refresh(now: first.addingTimeInterval(45))

        // The failed fetch changes nothing: same snapshot, same last success.
        #expect(store.snapshot == good)
        #expect(store.lastSuccess == first)
    }

    @Test func startsEmptyWhenTheFirstFetchFails() async {
        let store = NightShiftStore { throw NightShiftFeedError.missingKey }

        await store.refresh()

        #expect(store.snapshot == nil)
        #expect(store.lastSuccess == nil)
        #expect(!store.isStale())
    }

    @Test func pollsFasterAndGoesStaleSoonerWhileLive() async throws {
        let live = try NightShiftSnapshot.decode(Data(Self.liveJSON.utf8))
        let store = NightShiftStore { live }
        let fetchedAt = Self.date("2026-10-27T22:00:00Z")

        await store.refresh(now: fetchedAt)

        #expect(store.pollInterval == 45)
        #expect(!store.isStale(now: fetchedAt.addingTimeInterval(135)))
        #expect(store.isStale(now: fetchedAt.addingTimeInterval(136)))
    }

    // MARK: - Lines on Screen

    @Test func cardWordingForEachStatus() throws {
        let now = Self.date("2026-10-27T18:00:00Z") // 3 pm Atlantic, Tuesday
        let session = NightShiftSnapshot.Session(
            date: "2026-10-27",
            startsAt: Self.date("2026-10-27T21:00:00Z"), // 6 pm Atlantic
            endsAt: Self.date("2026-10-28T01:00:00Z")
        )
        let here = NightShiftSnapshot.Here(total: 46, onSite: 37, remote: 9, people: [])

        func snapshot(_ status: NightShiftSnapshot.Status) -> NightShiftSnapshot {
            NightShiftSnapshot(status: status, session: session, standup: nil, pizza: nil, here: here, activity: nil, updatedAt: now)
        }

        #expect(snapshot(.live).cardTitle(now: now, calendar: Self.calendar) == "Night Shift tonight")
        #expect(snapshot(.scheduled).cardTitle(now: now, calendar: Self.calendar) == "Night Shift tonight")
        #expect(snapshot(.scheduled).cardTitle(now: now.addingTimeInterval(-2 * 86_400), calendar: Self.calendar) == "Night Shift Tuesday")
        #expect(snapshot(.cancelled).cardTitle(now: now, calendar: Self.calendar) == "Night Shift cancelled tonight")
        #expect(snapshot(.ended).cardTitle(now: now, calendar: Self.calendar) == nil)
        #expect(snapshot(.none).cardTitle(now: now, calendar: Self.calendar) == nil)

        #expect(snapshot(.scheduled).startsLine(calendar: Self.calendar) == "Starts at 6 pm")
        #expect(snapshot(.live).startsLine(calendar: Self.calendar) == nil)
        #expect(snapshot(.live).hereLabel == "here now, 9 remote")
        #expect(snapshot(.live).hereBreakdown == "37 on site, 9 remote")
        #expect(snapshot(.live).sessionLine(calendar: Self.calendar) == "Night Shift, Tuesday 27 October, 6:00 pm to 10:00 pm")
    }

    /// The card shows from 1 hour before the session starts until it ends.
    @Test func cardShowsOnlyDuringTheEvening() {
        let session = NightShiftSnapshot.Session(
            date: "2026-10-27",
            startsAt: Self.date("2026-10-27T21:00:00Z"), // 6 pm Atlantic
            endsAt: Self.date("2026-10-28T01:00:00Z") // 10 pm Atlantic
        )

        func shows(_ status: NightShiftSnapshot.Status, at time: String, session: NightShiftSnapshot.Session? = session) -> Bool {
            NightShiftSnapshot(status: status, session: session, standup: nil, pizza: nil, here: nil, activity: nil, updatedAt: Self.date(time))
                .showsCard(now: Self.date(time))
        }

        #expect(!shows(.scheduled, at: "2026-10-27T15:00:00Z")) // noon
        #expect(!shows(.scheduled, at: "2026-10-27T19:59:59Z")) // 4:59:59 pm
        #expect(shows(.scheduled, at: "2026-10-27T20:00:00Z")) // 5 pm, 1 hour before
        #expect(shows(.live, at: "2026-10-27T23:00:00Z")) // 8 pm
        #expect(shows(.cancelled, at: "2026-10-27T20:30:00Z"))
        #expect(shows(.live, at: "2026-10-28T00:59:59Z")) // just before 10 pm
        #expect(!shows(.live, at: "2026-10-28T01:00:00Z")) // 10 pm, ended
        #expect(!shows(.ended, at: "2026-10-27T23:00:00Z"))
        #expect(!shows(.none, at: "2026-10-27T23:00:00Z"))
        #expect(!shows(.scheduled, at: "2026-10-27T23:00:00Z", session: nil))
    }

    /// A cached "live" snapshot must not keep the page up after the session ends
    /// (for example when the feed is down overnight).
    @Test func pageShowsOnlyWhileTheSessionRuns() {
        let session = NightShiftSnapshot.Session(
            date: "2026-10-27",
            startsAt: Self.date("2026-10-27T21:00:00Z"),
            endsAt: Self.date("2026-10-28T01:00:00Z")
        )

        func shows(_ status: NightShiftSnapshot.Status, at time: String) -> Bool {
            NightShiftSnapshot(status: status, session: session, standup: nil, pizza: nil, here: nil, activity: nil, updatedAt: Self.date(time))
                .showsPage(now: Self.date(time))
        }

        #expect(shows(.live, at: "2026-10-27T23:00:00Z"))
        #expect(!shows(.live, at: "2026-10-28T01:00:00Z")) // session over
        #expect(!shows(.live, at: "2026-10-28T14:00:00Z")) // next day, feed still down
        #expect(!shows(.scheduled, at: "2026-10-27T23:00:00Z"))
    }

    @Test func pizzaCountdown() {
        let now = Self.date("2026-10-27T22:18:00Z") // 7:18 pm Atlantic

        func pizza(_ at: Date?, arrived: Bool = false) -> NightShiftSnapshot {
            NightShiftSnapshot(status: .live, session: nil, standup: nil, pizza: .init(at: at, arrived: arrived), here: nil, activity: nil, updatedAt: now)
        }

        let soon = pizza(Self.date("2026-10-27T22:30:00Z")) // 7:30 pm Atlantic
        let oneSecondLater = now.addingTimeInterval(1)
        #expect(soon.pizzaCountdown(now: oneSecondLater) == "11:59")
        #expect(soon.pizzaDetail(now: oneSecondLater, calendar: Self.calendar) == "until 7:30 pm")
        #expect(soon.pizzaLine(now: oneSecondLater) == "Pizza in 11:59")

        #expect(pizza(now.addingTimeInterval(65)).pizzaCountdown(now: now) == "1:05")
        #expect(pizza(now.addingTimeInterval(90 * 60)).pizzaCountdown(now: now) == "1 hr 30 min")

        let due = pizza(now.addingTimeInterval(-60))
        #expect(due.pizzaCountdown(now: now) == nil)
        #expect(due.pizzaLine(now: now) == "Pizza any minute")

        let arrived = pizza(nil, arrived: true)
        #expect(arrived.pizzaCountdown(now: now) == nil)
        #expect(arrived.pizzaLine(now: now) == "Pizza's here")
        #expect(pizza(nil).pizzaLine(now: now) == nil)
    }

    @Test func standupWordingAndFinishedTasks() throws {
        let snapshot = try NightShiftSnapshot.decode(Data(Self.liveJSON.utf8))
        let before = Self.date("2026-10-27T22:00:00Z") // 6 pm Atlantic; stand-up is 7:30 pm
        let after = before.addingTimeInterval(3_600)

        #expect(snapshot.standupDetail(now: before, calendar: Self.calendar) == "At 7:30 pm")
        #expect(snapshot.standupLine(now: before, calendar: Self.calendar) == "Stand-up at 7:30 pm")
        #expect(snapshot.standupDetail(now: after, calendar: Self.calendar) == "Was at 7:30 pm")
        #expect(snapshot.standupLine(now: after, calendar: Self.calendar) == "Stand-up was at 7:30 pm")
        // Only "finished" items, newest first.
        #expect(snapshot.finishedTasks.map(\.initials) == ["CM", "AK"])
    }

    @Test func minutesAgo() {
        let now = Self.date("2026-10-27T22:00:00Z")
        #expect(NightShiftFormat.ago(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(NightShiftFormat.ago(now.addingTimeInterval(-60), now: now) == "1 min ago")
        #expect(NightShiftFormat.ago(now.addingTimeInterval(-8 * 60 - 30), now: now) == "8 min ago")
        #expect(NightShiftFormat.ago(now.addingTimeInterval(-2 * 3_600), now: now) == "2 hr ago")
    }

    // MARK: - Live Fetch

    /// One test, in order, because the stub's state is shared.
    @Test func liveFetchSendsTheKeyAndChecksTheStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = NightShiftFeed.liveURL

        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(Self.liveJSON.utf8)
        let snapshot = try await NightShiftFeed.fetch(url: url, key: "test-key", session: session)
        #expect(snapshot.status == .live)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        StubURLProtocol.status = 401
        do {
            _ = try await NightShiftFeed.fetch(url: url, key: "test-key", session: session)
            Issue.record("Expected HTTP 401 to throw")
        } catch NightShiftFeedError.badStatus(let code) {
            #expect(code == 401)
        }

        StubURLProtocol.lastRequest = nil
        do {
            _ = try await NightShiftFeed.fetch(url: url, key: "", session: session)
            Issue.record("Expected an empty key to throw")
        } catch NightShiftFeedError.missingKey {
            #expect(StubURLProtocol.lastRequest == nil) // nothing was sent
        }
    }

    // MARK: - Merge Guard

    /// Fails on purpose while the TV runs on sample data, so this branch
    /// can't be merged before the Foundry feed is switched on.
    @Test func liveFeedIsSwitchedOnBeforeMerge() {
        if case .sample = NightShiftFeed.source {
            Issue.record("Set NightShiftFeed.source = .live(liveURL) before merging.")
        }
    }
}

/// Answers every request with a canned status and body, and keeps the request.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
