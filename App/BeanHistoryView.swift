import DialShotKit
import DialShotStore
import SwiftUI

struct BeanHistoryView: View {
    let persistence: ShotPersistence
    @State private var beans: [BeanBag] = []
    @State private var shots: [HistoryShot] = []
    @State private var selectedBeanID: BeanBag.ID?
    @State private var activeRecipe: RecipeRecord?
    @State private var recipes: [RecipeRecord] = []
    @State private var beanQuery = ""
    @State private var grinderQuery = ""
    @State private var verdict: TasteVerdict?
    @State private var fromEnabled = false
    @State private var throughEnabled = false
    @State private var fromDate = Date()
    @State private var throughDate = Date()
    @State private var selectedShotIDs: Set<UUID> = []
    @State private var showComparison = false
    @State private var error: String?

    private var filtered: [HistoryShot] {
        let end = throughEnabled ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: throughDate))?.addingTimeInterval(-0.001) : nil
        let filter = HistoryFilter(beanQuery: beanQuery, grinderQuery: grinderQuery,
                                   from: fromEnabled ? Calendar.current.startOfDay(for: fromDate) : nil,
                                   through: end, tasteVerdict: verdict)
        return ShotHistory.filter(shots, using: filter).filter {
            selectedBeanID == nil || $0.attempt.recipe.beanID == selectedBeanID
        }
    }

    private var selectedShots: [HistoryShot] {
        filtered.filter { selectedShotIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section("Bean") {
                Picker("Bean", selection: $selectedBeanID) {
                    Text("All beans").tag(nil as BeanBag.ID?)
                    ForEach(beans) { bean in
                        Text(bean.name).tag(Optional(bean.id))
                    }
                }
                .accessibilityIdentifier("history.beanPicker")
                if let selectedBeanID {
                    if let activeRecipe {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dialed-in recipe").font(.headline)
                            Text(activeRecipe.name ?? "Current recipe")
                            Text("Dose \(activeRecipe.snapshot.doseGrams) g · Target \(activeRecipe.snapshot.targetYieldGrams) g · \(activeRecipe.snapshot.targetTimeSeconds) s")
                            Text("Ratio \(activeRecipe.snapshot.targetRatio.displayString)")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("bean.activeRecipe")
                    } else {
                        Text("No active recipe for this bean")
                            .accessibilityIdentifier("bean.activeRecipe")
                    }
                    if !recipes.isEmpty {
                        ForEach(recipes) { record in
                            Button {
                                do {
                                    try persistence.setActive(record)
                                    activeRecipe = record
                                    error = nil
                                } catch { self.error = "Could not select recipe: \(error.localizedDescription)" }
                            } label: {
                                HStack {
                                    Text(record.name ?? "Recipe \(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    if record.id == activeRecipe?.id { Text("Dialed in").font(.caption) }
                                }
                            }
                            .accessibilityLabel("Use \(record.name ?? "recipe") as dialed-in recipe")
                        }
                    }
                    let trend = ShotTrend(shots.filter { $0.attempt.recipe.beanID == selectedBeanID })
                    trendView(trend)
                } else {
                    Text("Choose a bean to see its recipe and trend")
                        .accessibilityIdentifier("history.trend")
                }
            }

            Section("Search and filter") {
                TextField("Search bean", text: $beanQuery)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("history.beanSearch")
                TextField("Search grinder", text: $grinderQuery)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("history.grinderSearch")
                Picker("Taste verdict", selection: $verdict) {
                    Text("Any taste").tag(nil as TasteVerdict?)
                    Text("Under-extracted").tag(Optional(TasteVerdict.underExtracted))
                    Text("Balanced").tag(Optional(TasteVerdict.balanced))
                    Text("Over-extracted").tag(Optional(TasteVerdict.overExtracted))
                }
                .accessibilityIdentifier("history.verdict")
                Toggle("From date", isOn: $fromEnabled)
                if fromEnabled { DatePicker("From", selection: $fromDate, displayedComponents: .date) }
                Toggle("Through date", isOn: $throughEnabled)
                if throughEnabled { DatePicker("Through", selection: $throughDate, displayedComponents: .date) }
            }

            Section {
                Button("Compare two shots (\(selectedShots.count)/2)") { showComparison = true }
                    .disabled(selectedShots.count != 2)
                    .accessibilityIdentifier("history.compare")
            }

            Section("Shot history · oldest first") {
                if filtered.isEmpty {
                    Text("No shots match these filters")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("history.empty")
                }
                ForEach(filtered) { shot in
                    Button { toggle(shot.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(shot.attempt.createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.headline)
                            Text("\(shot.beanName) · \(shot.grinderName)")
                            Text("\(shot.attempt.recipe.doseGrams) g in · \(shot.attempt.measuredYieldGrams) g out · \(shot.attempt.elapsedSeconds) s")
                            Text("Taste: \(tasteText(shot.attempt.observation.tasteVerdict))")
                            Text("Setting: \(shot.grinderSetting ?? "Not recorded")")
                            Text(selectedShotIDs.contains(shot.id) ? "Selected for comparison" : "Select for comparison")
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(shot.beanName), \(shot.attempt.elapsedSeconds) seconds, \(tasteText(shot.attempt.observation.tasteVerdict)), \(selectedShotIDs.contains(shot.id) ? "selected" : "not selected")")
                    .accessibilityAddTraits(selectedShotIDs.contains(shot.id) ? [.isSelected] : [])
                    .accessibilityIdentifier("history.shot.\(shot.id.uuidString)")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Beans & history")
        .onAppear(perform: load)
        .onChange(of: selectedBeanID) { _, beanID in
            selectedShotIDs.removeAll()
            do {
                try persistence.selectBean(beanID)
                try loadActiveRecipe()
                error = nil
            } catch {
                activeRecipe = nil
                recipes = []
                self.error = "Could not load recipe: \(error.localizedDescription)"
            }
        }
        .onChange(of: filtered.map(\.id)) { _, visibleIDs in
            selectedShotIDs.formIntersection(Set(visibleIDs))
        }
        .sheet(isPresented: $showComparison) {
            if let comparison = try? ShotComparison(selectedShots) {
                NavigationStack { ShotComparisonView(comparison: comparison) }
            }
        }
    }

    private func trendView(_ trend: ShotTrend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shot trend").font(.headline)
            if trend.points.isEmpty {
                Text("No shots yet")
            } else {
                Text("Extraction time: \(trend.points.map { "\($0.elapsedSeconds) s" }.joined(separator: " → "))")
                Text("Sensory balance: \(trend.points.map { balanceText($0.sensoryBalance) }.joined(separator: " → "))")
                if let change = trend.timeChangeSeconds {
                    Text("First to latest: \(change >= 0 ? "+" : "")\(change) s")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.trend")
    }

    private func toggle(_ id: UUID) {
        if selectedShotIDs.contains(id) { selectedShotIDs.remove(id) }
        else if selectedShotIDs.count < 2 {
            if let first = selectedShots.first,
               let next = shots.first(where: { $0.id == id }),
               first.attempt.recipe.beanID != next.attempt.recipe.beanID {
                selectedShotIDs = [id]
            } else {
                selectedShotIDs.insert(id)
            }
        }
    }

    private func load() {
        do {
            beans = try persistence.beanList()
            shots = try persistence.history()
            if selectedBeanID == nil, let remembered = persistence.selectedBeanID,
               beans.contains(where: { $0.id == remembered }) {
                selectedBeanID = remembered
            }
            try loadActiveRecipe()
            error = nil
        } catch { self.error = "Could not load history: \(error.localizedDescription)" }
    }

    private func loadActiveRecipe() throws {
        activeRecipe = try selectedBeanID.flatMap { try persistence.activeRecipe(for: $0) }
        recipes = try selectedBeanID.map { try persistence.recipeList(for: $0) } ?? []
    }
}

private func tasteText(_ verdict: TasteVerdict?) -> String {
    switch verdict {
    case .underExtracted: "Under-extracted"
    case .balanced: "Balanced"
    case .overExtracted: "Over-extracted"
    case nil: "Unknown"
    }
}

private func balanceText(_ balance: SensoryBalance) -> String {
    switch balance {
    case .underExtracted: "Under-extracted"
    case .balanced: "Balanced"
    case .overExtracted: "Over-extracted"
    case .unknown: "Unknown"
    }
}

private struct ShotComparisonView: View {
    let comparison: ShotComparison
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 16) {
                column(comparison.first, title: "Earlier shot")
                column(comparison.second, title: "Later shot")
            }
            .padding()
        }
        .navigationTitle("Compare shots")
        .toolbar { Button("Done") { dismiss() } }
        .accessibilityIdentifier("comparison.view")
    }

    private func column(_ shot: HistoryShot, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            Text(shot.attempt.createdAt, format: .dateTime.day().month().year().hour().minute())
            row("Dose", "\(shot.attempt.recipe.doseGrams) g", different: comparison.doseDifferent)
            row("Yield", "\(shot.attempt.measuredYieldGrams) g", different: comparison.yieldDifferent)
            row("Time", "\(shot.attempt.elapsedSeconds) s", different: comparison.timeDifferent)
            row("Grinder", shot.grinderName, different: comparison.first.attempt.recipe.grinderID != comparison.second.attempt.recipe.grinderID)
            row("Setting", shot.grinderSetting ?? "Not recorded", different: comparison.grinderSettingDifferent)
            row("Taste", tasteText(shot.attempt.observation.tasteVerdict), different: comparison.tasteDifferent)
            row("Flow", shot.attempt.observation.flowVerdict?.rawValue ?? "Unknown", different: comparison.flowDifferent)
            row("Sensory notes", shot.attempt.observation.notes.isEmpty ? "None recorded" : shot.attempt.observation.notes.map(\.rawValue).joined(separator: ", "), different: comparison.notesDifferent)
        }
        .frame(width: 240, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func row(_ name: String, _ value: String, different: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
            if different == true { Text("Different").font(.caption.bold()).foregroundStyle(.orange) }
            if different == nil { Text("Comparison unknown").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(different == true ? Color.orange.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(value). \(different == true ? "Different" : different == nil ? "Comparison unknown" : "Same")")
    }
}
