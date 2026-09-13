import SwiftUI

/// Heptabase's Journal: a strip of days with a dot on each that has an
/// entry, and the chosen day's note beneath. Entries are files named by
/// date in the vault's journal directory (`canvas.config.json`, `journal`).
struct JournalView: View {
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        let path = store.journalPath
        let days = store.journalDays()
        VStack(spacing: 0) {
            strip(days: days)
            Divider()
            if vault.exists(path) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        dayHeading
                        FileInspector(path: path, store: store, embedded: true)
                            .id(path)
                    }
                }
            } else {
                VStack(spacing: Space.m) {
                    dayHeading
                    Text("No entry for this day.")
                        .font(Typography.body)
                        .foregroundStyle(Ink.muted)
                    Button("Start this day's note") { store.createJournalEntry() }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Ink.card)
    }

    private var dayHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.journalDate.formatted(.dateTime.weekday(.wide)))
                .font(Typography.label)
                .foregroundStyle(Color(light: "E5484D", dark: "FF6B6B"))
            Text(store.journalDate.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(Typography.figure)
                .foregroundStyle(Ink.primary)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
    }

    private func strip(days: Set<String>) -> some View {
        HStack(spacing: 2) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, Space.xs)
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
            ForEach(-3...3, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: store.journalDate) ?? store.journalDate
                let key = JournalConfig.formatter.string(from: day)
                let selected = offset == 0
                Button {
                    store.journalDate = day
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(days.contains(key) ? (selected ? Color.white : Accent.text) : .clear)
                            .frame(width: 5, height: 5)
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(Typography.meta)
                        Text(day.formatted(.dateTime.day()))
                            .font(Typography.label)
                    }
                    .foregroundStyle(selected ? Color.white : Ink.primary)
                    .fixedSize()
                    .padding(.horizontal, Space.s)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(selected ? Accent.text : .clear))
                }
                .buttonStyle(.plain)
            }
            }
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, Space.xs)
            Button("Today") { store.journalDate = Date() }
                .font(Typography.control)
                .fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(height: 44)
    }

    private func shift(_ days: Int) {
        store.journalDate = calendar.date(byAdding: .day, value: days, to: store.journalDate) ?? store.journalDate
    }
}
