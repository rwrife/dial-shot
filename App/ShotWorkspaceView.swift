import DialShotKit
import SwiftUI
import UIKit

/// Issue #6: every piece of content is placed through `ShotWorkspaceLayout`
/// for the coordinator's current mode, and all continuity state (timer,
/// draft, yield text, comparison selection) lives in the environment-level
/// `ShotWorkspaceCoordinator`, not in view storage. Standard iPhones resolve
/// to `.compact`; a future dual-screen adapter changes only how contents map
/// to panes here — never the state itself.
struct ShotWorkspaceView: View {
    @Environment(ShotWorkspaceCoordinator.self) private var workspace
    @State private var persistence: ShotPersistence?
    @State private var review: ShotReview?
    @State private var message: String?
    @FocusState private var yieldFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 72

    private let noteChoices: [(SensoryNote, String)] = [
        (.sour, "Sour"), (.balanced, "Balanced"), (.bitter, "Bitter"),
        (.astringent, "Astringent"), (.channeling, "Channel / spurting")
    ]
    private let flowChoices: [(FlowVerdict, String)] = [
        (.fast, "Fast"), (.onTarget, "On target"), (.slow, "Slow")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(ShotWorkspaceLayout.visibleContents(mode: workspace.layoutMode, pane: .primary), id: \.self) { content in
                        workspaceContent(content)
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Dial Shot")
            .safeAreaInset(edge: .bottom, spacing: 0) { controlDock }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { yieldFocused = false }
                }
            }
        }
        .task { openStore() }
        .onAppear { syncDraftWithRecipe() }
    }

    /// The seam: each `WorkspaceContent` resolves to exactly one on-screen
    /// view here. `captureControls` renders in the dock below because it is
    /// primary-pane chrome in every mode.
    @ViewBuilder
    private func workspaceContent(_ content: WorkspaceContent) -> some View {
        switch content {
        case .shotHistoryAccess:
            if let persistence {
                NavigationLink("Beans & history") {
                    BeanHistoryView(persistence: persistence)
                }
                .accessibilityIdentifier("history.open")
            }
        case .recipeContext:
            if workspace.draft?.recipe != nil || persistence?.recipe != nil {
                Text("Dose \(doseText) g · Target \(targetText) g")
                    .font(.headline)
                    .accessibilityIdentifier("recipe.summary")
            } else {
                Text("No recipe in this backup. Restore a backup with a recipe to capture shots.")
                    .font(.headline)
                    .accessibilityIdentifier("recipe.empty")
            }
        case .shotTimer:
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(timeText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Shot time, \(timeText)")
                    .accessibilityIdentifier("timer.elapsed")
            }
        case .captureForm:
            if workspace.draft?.timer.phase == .stopped {
                captureForm
            }
        case .adjustmentRationale:
            if let review {
                reviewPanel(review)
            }
        case .shotMessage:
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("capture.message")
            }
        case .captureControls:
            EmptyView()
        }
    }

    private var controlDock: some View {
        VStack(spacing: 8) {
            if workspace.draft?.timer.phase == .running, workspace.draft?.timer.firstDropSeconds == nil {
                Button {
                    _ = workspace.draft?.markFirstDrop()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("First drop")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("Mark first drop")
                .accessibilityIdentifier("timer.firstDrop")
            }

            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryTint)
            .foregroundStyle(.white)
            .accessibilityLabel(primaryTitle + " shot")
            .accessibilityIdentifier("timer.primary")
            .disabled(workspace.draft == nil || workspace.draft?.timer.phase == .stopped)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var captureForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField(
                "Actual yield (g)",
                text: Binding(
                    get: { workspace.yieldInputText },
                    set: { workspace.yieldInputText = $0 }
                )
            )
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .focused($yieldFocused)
            .accessibilityLabel("Actual yield in grams")
            .accessibilityIdentifier("capture.yield")
            .onChange(of: workspace.yieldInputText) { _, _ in review = nil }

            Text("Taste and flow").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(noteChoices.indices, id: \.self) { index in
                    let (note, title) = noteChoices[index]
                    chip(title, selected: workspace.draft?.notes.contains(note) == true, id: "note.\(note.rawValue)") {
                        if workspace.draft?.notes.contains(note) == true { workspace.draft?.notes.remove(note) }
                        else { workspace.draft?.notes.insert(note) }
                        review = nil
                    }
                }
            }
            Text("Flow").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(flowChoices.indices, id: \.self) { index in
                    let (flow, title) = flowChoices[index]
                    chip(title, selected: workspace.draft?.flowVerdict == flow, id: "flow.\(flow.rawValue)") {
                        // Read before mutate: `draft` is an @Observable class
                        // property, so a combined read-modify-write keeps the
                        // setter's exclusive access open while the expression
                        // reads it back — a fatal exclusivity conflict.
                        let current = workspace.draft?.flowVerdict
                        workspace.draft?.flowVerdict = current == flow ? nil : flow
                        review = nil
                    }
                }
            }

            Button("Review shot") { prepareReview() }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.review")

            Button("Discard shot") {
                if let recipe = persistence?.recipe { workspace.installDraft(recipe: recipe) }
                review = nil
                message = nil
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("capture.discard")
        }
    }

    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.bold())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .primary : .accentColor)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    private func reviewPanel(_ review: ShotReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review before saving").font(.title2.bold())
            Text("Dose: \(doseText) g")
            Text("Actual yield: \(review.attempt.measuredYieldGrams) g")
            Text("Ratio: \(review.attempt.brewRatio.displayString)")
            Text("Total time: \(review.attempt.elapsedSeconds) s")
            if let firstDrop = review.attempt.firstDropSeconds {
                Text("First drop: \(firstDrop) s")
            }
            Text(suggestionText(review.suggestion))
                .font(.headline)
                .accessibilityIdentifier("review.suggestion")
            Button("Save shot") { save(review) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("review.save")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func suggestionText(_ suggestion: DialInSuggestion) -> String {
        switch suggestion {
        case .adjustment(let adjustment):
            let action: String
            switch adjustment.action {
            case .grindFiner: action = "Grind finer"
            case .grindCoarser: action = "Grind coarser"
            case .increaseYieldRatio: action = "Increase yield ratio"
            case .decreaseYieldRatio: action = "Decrease yield ratio"
            }
            return "Recommendation: \(action). \(adjustment.rationale)"
        case .noChangeRecommended:
            return "Recommendation: No change recommended."
        case .insufficientEvidence(let reason):
            return "Recommendation: Insufficient evidence. \(reason)"
        }
    }

    private var primaryTitle: String {
        switch workspace.draft?.timer.phase {
        case .running: "Stop"
        case .stopped: "Stopped"
        default: "Start"
        }
    }

    private var primaryTint: Color {
        switch workspace.draft?.timer.phase {
        case .running: .red
        default: .black
        }
    }

    private var doseText: String { (workspace.draft?.recipe ?? persistence?.recipe)?.doseGrams.description ?? "18" }
    private var targetText: String { (workspace.draft?.recipe ?? persistence?.recipe)?.targetYieldGrams.description ?? "36" }
    private var timeText: String {
        guard var draft = workspace.draft else { return "0:00" }
        let seconds = draft.elapsedSeconds()
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func primaryAction() {
        if workspace.draft?.timer.phase == .idle {
            workspace.draft?.start()
            message = nil
        } else if workspace.draft?.timer.phase == .running {
            workspace.draft?.stop()
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func prepareReview() {
        guard let grams = Decimal(string: workspace.yieldInputText, locale: .current) else {
            message = "Enter a valid actual yield."
            return
        }
        workspace.draft?.measuredYieldGrams = grams
        do {
            review = try workspace.draft?.review()
            message = nil
        } catch {
            message = "Cannot review shot: \(error.localizedDescription)"
        }
    }

    private func save(_ review: ShotReview) {
        guard let persistence else {
            message = "Local storage is unavailable."
            return
        }
        do {
            try persistence.save(review)
            if let recipe = persistence.recipe { workspace.installDraft(recipe: recipe) }
            self.review = nil
            message = "Shot saved on this iPhone."
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }

    private func openStore() {
        guard persistence == nil else { return }
        do {
            let store = try ShotPersistence()
            persistence = store
            // Continuity: a draft already in progress (view rebuild) is never
            // clobbered by a re-run of the store open.
            if workspace.draft == nil, let recipe = store.recipe {
                workspace.installDraft(recipe: recipe)
            }
        } catch {
            message = "Could not open local storage: \(error.localizedDescription)"
        }
    }

    private func syncDraftWithRecipe() {
        guard let persistence, workspace.draft?.timer.phase == .idle,
              let recipe = persistence.recipe,
              workspace.draft?.recipe != recipe else { return }
        workspace.draft = ShotCapture(recipe: recipe)
    }
}
