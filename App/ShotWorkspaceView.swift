import DialShotKit
import SwiftUI
import UIKit

struct ShotWorkspaceView: View {
    @State private var persistence: ShotPersistence?
    @State private var capture: ShotCapture?
    @State private var review: ShotReview?
    @State private var yieldText = ""
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
                    if let persistence {
                        NavigationLink("Beans & history") {
                            BeanHistoryView(persistence: persistence)
                        }
                        .accessibilityIdentifier("history.open")
                    }
                    Text("Dose \(doseText) g · Target \(targetText) g")
                        .font(.headline)
                        .accessibilityIdentifier("recipe.summary")

                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        Text(timeText)
                            .font(.system(size: timerFontSize, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Shot time, \(timeText)")
                            .accessibilityIdentifier("timer.elapsed")
                    }

                    if capture?.timer.phase == .stopped {
                        captureForm
                    }

                    if let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("capture.message")
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
        .onAppear {
            if let persistence, capture?.timer.phase == .idle,
               capture?.recipe != persistence.recipe {
                capture = ShotCapture(recipe: persistence.recipe)
            }
        }
    }

    private var controlDock: some View {
        VStack(spacing: 8) {
            if capture?.timer.phase == .running, capture?.timer.firstDropSeconds == nil {
                Button {
                    _ = capture?.markFirstDrop()
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
            .disabled(capture == nil || capture?.timer.phase == .stopped)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var captureForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Actual yield (g)", text: $yieldText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($yieldFocused)
                .accessibilityLabel("Actual yield in grams")
                .accessibilityIdentifier("capture.yield")
                .onChange(of: yieldText) { _, _ in review = nil }

            Text("Taste and flow").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(noteChoices.indices, id: \.self) { index in
                    let (note, title) = noteChoices[index]
                    chip(title, selected: capture?.notes.contains(note) == true, id: "note.\(note.rawValue)") {
                        if capture?.notes.contains(note) == true { capture?.notes.remove(note) }
                        else { capture?.notes.insert(note) }
                        review = nil
                    }
                }
            }
            Text("Flow").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(flowChoices.indices, id: \.self) { index in
                    let (flow, title) = flowChoices[index]
                    chip(title, selected: capture?.flowVerdict == flow, id: "flow.\(flow.rawValue)") {
                        capture?.flowVerdict = capture?.flowVerdict == flow ? nil : flow
                        review = nil
                    }
                }
            }

            Button("Review shot") { prepareReview() }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.review")

            if let review {
                reviewPanel(review)
            }

            Button("Discard shot") {
                capture = persistence.map { ShotCapture(recipe: $0.recipe) }
                review = nil
                yieldText = ""
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
        switch capture?.timer.phase {
        case .running: "Stop"
        case .stopped: "Stopped"
        default: "Start"
        }
    }

    private var primaryTint: Color {
        switch capture?.timer.phase {
        case .running: .red
        default: .black
        }
    }

    private var doseText: String { capture?.recipe.doseGrams.description ?? "18" }
    private var targetText: String { capture?.recipe.targetYieldGrams.description ?? "36" }
    private var timeText: String {
        guard var draft = capture else { return "0:00" }
        let seconds = draft.elapsedSeconds()
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func primaryAction() {
        if capture?.timer.phase == .idle {
            capture?.start()
            message = nil
        } else if capture?.timer.phase == .running {
            capture?.stop()
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func prepareReview() {
        guard let grams = Decimal(string: yieldText, locale: .current) else {
            message = "Enter a valid actual yield."
            return
        }
        capture?.measuredYieldGrams = grams
        do {
            review = try capture?.review()
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
            capture = ShotCapture(recipe: persistence.recipe)
            self.review = nil
            yieldText = ""
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
            capture = ShotCapture(recipe: store.recipe)
        } catch {
            message = "Could not open local storage: \(error.localizedDescription)"
        }
    }
}
