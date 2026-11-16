import SwiftUI

/// Lets the user choose the target colour by name, for when the manual's print reads wrong.
struct TargetPicker: View {
    var title = "Target colour"
    let palette: [LegoColor]
    /// The set the palette comes from, if any.
    let legoSet: LegoSet?
    let onPick: (LegoColor) -> Void

    enum Sort: String {
        case name
        case bricks
    }

    @State private var search = ""
    @AppStorage("colorSort") private var sort = Sort.name
    @Environment(\.dismiss) private var dismiss

    private var brickCounts: [LegoColor: Int] { legoSet?.brickCounts ?? [:] }

    private var allColors: [LegoColor] {
        let counts = brickCounts
        return palette
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted {
                let a = counts[$0] ?? 0, b = counts[$1] ?? 0
                return sort == .bricks && a != b ? a > b : $0.name < $1.name
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if legoSet != nil {
                    Picker("Sort by", selection: $sort) {
                        Text("Name").tag(Sort.name)
                        Text("Most bricks").tag(Sort.bricks)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section(legoSet.map { "Colours in \($0.name)" } ?? "Common colours") {
                    ForEach(allColors) { row($0) }
                }
            }
            .searchable(text: $search)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ color: LegoColor) -> some View {
        Button {
            onPick(color)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Swatch(color: color)
                Text(color.name).foregroundStyle(.primary)
                if let count = brickCounts[color] {
                    Spacer()
                    Text(count == 1 ? "1 brick" : "\(count) bricks")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Search for the set being built, so only its colours are offered.
struct SetPicker: View {
    let selected: LegoSet?
    let onPick: (LegoSet?) -> Void

    @State private var search = ""
    @State private var results: [LegoSet] = []
    @State private var isLoaded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section("Current set") {
                        row(selected)
                        Button("Use common colours instead", systemImage: "xmark.circle") {
                            onPick(nil)
                            dismiss()
                        }
                    }
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { row($0) }
                    }
                }
                Section {
                } footer: {
                    Text("Set data from Rebrickable. Transparent colours are not included.")
                }
            }
            .overlay {
                if !isLoaded {
                    ProgressView()
                } else if results.isEmpty && selected == nil {
                    if search.isEmpty {
                        ContentUnavailableView(
                            "Find your set",
                            systemImage: "shippingbox",
                            description: Text("Search by the number on the box or manual, or by name.")
                        )
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Set number or name")
            .navigationTitle("Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: search) {
                let query = search
                let found = await Task.detached { SetCatalog.search(query) }.value
                if !Task.isCancelled {
                    results = found
                    isLoaded = true
                }
            }
        }
    }

    private func row(_ set: LegoSet) -> some View {
        Button {
            onPick(set)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.headline).foregroundStyle(.primary)
                Text("\(set.displayNumber) · \(String(set.year)) · \(set.colors.count) colours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HelpView: View {
    /// Clears the colours the user has taught the app; nil when there are none.
    var onForget: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                step("lightbulb.fill", "Light it", "In a dim room, turn on Light. Hold the phone about a hand's width away.")
                step("circle.lefthalf.filled", "Set white", "Aim the circle at plain white paper and tap Set white. This removes the colour of the room light. Redo it when the light changes.")
                step("shippingbox.fill", "Choose your set", "Optional, but it helps: tap Choose set and find your set. Only the colours in that set are then considered.")
                step("scope", "Set target", "Aim the circle at the brick in the manual and tap Set target. If the name looks wrong, tap it at the top to pick another.")
                step("checkmark.circle.fill", "Find the brick", "Point at your bricks. Bricks of the target colour get a white outline, everything else is dimmed, and the phone taps when the circle is on a match.")
                step("graduationcap.fill", "Teach it", "If a brick you know is named wrong, aim at it, tap Wrong colour? and pick the right name. The app remembers how that colour looks to the camera.")
                Section {
                    Text("Light and dark versions of the same colour (Red and Dark Red, the two grays) are the hardest to tell apart. When the app says \"Maybe\", compare with a brick you know.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let onForget {
                    Section {
                        Button("Forget taught colours", role: .destructive) {
                            onForget()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ systemImage: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 4)
    }
}
