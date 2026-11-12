//
//  NightShiftViews.swift
//  bragboard
//
//  Night Shift slideshow page and dashboard card, laid out after the
//  Night Shift room-TV mock-up, in BragBoard's gradient-card style.
//

#if os(tvOS)
import SwiftUI

// MARK: - Page

struct NightShiftPageView: View {
    let store: NightShiftStore

    var body: some View {
        // Re-render every 30 s so "min ago" and stand-up wording move between polls.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            // Date() rather than the schedule's date, so "min ago" is never behind a fresh poll.
            content(now: Date())
                .padding(.horizontal, 60)
                .padding(.top, 50)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = store.snapshot, snapshot.showsPage(now: now) {
            VStack(spacing: 40) {
                header(snapshot, now: now)

                // Three equal columns, as in the mock-up.
                HStack(alignment: .top, spacing: 30) {
                    NightShiftHereCard(snapshot: snapshot)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 30) {
                        NightShiftStandupCard(snapshot: snapshot, now: now)
                        NightShiftPizzaCard(snapshot: snapshot)
                    }
                    .frame(maxWidth: .infinity)

                    NightShiftFinishedCard(tasks: snapshot.finishedTasks, now: now)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func header(_ snapshot: NightShiftSnapshot, now: Date) -> some View {
        VStack(spacing: 14) {
            Text("Tonight's Session")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if let line = snapshot.sessionLine() {
                Text(line)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            if store.isStale(now: now), let lastSuccess = store.lastSuccess {
                Text("Last updated \(NightShiftFormat.time(lastSuccess))")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A gradient card in TVWidgetContainer, like the other BragBoard cards.
private struct NightShiftCard<Content: View>: View {
    let colors: [Color]
    @ViewBuilder let content: Content

    var body: some View {
        TVWidgetContainer {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .background {
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.3) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
    }
}

/// Icon and title at the top of each card ("Here now", "Stand-up", …).
private struct NightShiftCardHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 36))
        .foregroundColor(.white.opacity(0.85))
    }
}

// MARK: - Here Now

private struct NightShiftHereCard: View {
    let snapshot: NightShiftSnapshot

    /// 4 rows of 8. Past that, the last slot becomes "+N".
    private let slots = 32

    var body: some View {
        NightShiftCard(colors: [.blue, .purple]) {
            VStack(alignment: .leading, spacing: 0) {
                NightShiftCardHeader(icon: "person.2", title: "Here now")

                Text("\(snapshot.here?.total ?? 0)")
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                if let breakdown = snapshot.hereBreakdown {
                    Text(breakdown)
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer(minLength: 24)

                avatarGrid
            }
        }
    }

    private var avatarGrid: some View {
        let people = snapshot.here?.people ?? []
        let shown = people.count > slots ? Array(people.prefix(slots - 1)) : people
        // The feed may cap the list, so count from the total.
        let hidden = max(snapshot.here?.total ?? 0, people.count) - shown.count

        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(50), spacing: 10), count: 8),
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, person in
                NightShiftAvatar(initials: person.initials, remote: person.remote, size: 50)
            }

            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
        }
    }
}

/// Initials in a circle. Remote people get a dashed ring and a laptop badge.
struct NightShiftAvatar: View {
    let initials: String
    let remote: Bool
    var size: CGFloat = 56

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.white.opacity(remote ? 0.06 : 0.16), in: Circle())
            .overlay {
                if remote {
                    Circle().strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if remote {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.8), in: Circle())
                        .offset(x: 4, y: 4)
                }
            }
            .accessibilityLabel(remote ? "\(initials), remote" : initials)
    }
}

// MARK: - Stand-up

private struct NightShiftStandupCard: View {
    let snapshot: NightShiftSnapshot
    let now: Date

    var body: some View {
        NightShiftCard(colors: [.green, .teal]) {
            VStack(alignment: .leading, spacing: 20) {
                NightShiftCardHeader(icon: "megaphone", title: "Stand-up")

                Text(snapshot.standupDetail(now: now) ?? "Not planned tonight")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundColor(snapshot.standup?.now == true ? .green : .white)
            }
        }
    }
}

// MARK: - Pizza

private struct NightShiftPizzaCard: View {
    let snapshot: NightShiftSnapshot

    var body: some View {
        NightShiftCard(colors: [.purple, .blue]) {
            VStack(alignment: .leading, spacing: 20) {
                NightShiftCardHeader(icon: "fork.knife", title: "Pizza")

                // The countdown ticks every second.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let countdown = snapshot.pizzaCountdown(now: context.date) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(countdown)
                                .font(.system(size: 80, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                                .monospacedDigit()

                            if let detail = snapshot.pizzaDetail(now: context.date) {
                                Text(detail)
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Text(snapshot.pizzaLine(now: context.date) ?? "No pizza tonight")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}

// MARK: - Just Finished

private struct NightShiftFinishedCard: View {
    let tasks: [NightShiftSnapshot.Activity]
    let now: Date

    private let maxRows = 6

    var body: some View {
        NightShiftCard(colors: [.blue, .teal]) {
            VStack(alignment: .leading, spacing: 16) {
                NightShiftCardHeader(icon: "checkmark.circle", title: "Just finished")

                if tasks.isEmpty {
                    Text("Nothing finished yet")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    ForEach(Array(tasks.prefix(maxRows).enumerated()), id: \.offset) { _, task in
                        HStack(spacing: 16) {
                            NightShiftAvatar(initials: task.initials, remote: false, size: 56)

                            Text(task.text)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(NightShiftFormat.ago(task.at, now: now))
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.6))
                                .monospacedDigit()
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Card

/// Top-left card on the dashboard while a night is scheduled, live or cancelled.
struct NightShiftCardView: View {
    let snapshot: NightShiftSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date

            VStack(alignment: .leading, spacing: 16) {
                if let title = snapshot.cardTitle(now: now) {
                    NightShiftCardHeader(icon: "moon", title: title)
                }

                if snapshot.status == .live {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(snapshot.here?.total ?? 0)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text(snapshot.hereLabel)
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.75))
                    }

                    if let countdown = snapshot.pizzaCountdown(now: now) {
                        Text("Pizza in \(Text(countdown).foregroundColor(.orange).bold())")
                            .monospacedDigit()
                    } else if let pizza = snapshot.pizzaLine(now: now) {
                        Text(pizza)
                    }

                    if let standup = snapshot.standupLine(now: now) {
                        Text(standup)
                    }
                } else if let starts = snapshot.startsLine() {
                    Text(starts)
                }

                Spacer(minLength: 0)
            }
            .font(.system(size: 30))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.3), Color.teal.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
#endif
