import SwiftUI

/// Statistiques réseau.
struct PerfView: View {
    @ObservedObject private var perf = Perf.shared

    var body: some View {
        List {
            if perf.statsByEndpoint.isEmpty {
                Text("Aucune requête enregistrée.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Par endpoint") {
                    ForEach(perf.statsByEndpoint) { stat in
                        HStack {
                            Text(stat.name).font(.subheadline)
                            Spacer()
                            Text("\(stat.count)×").foregroundStyle(.secondary).font(.caption)
                            Text("\(Int(stat.averageMs)) ms")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            Section("Journal") {
                ForEach(perf.entries.suffix(60).reversed()) { entry in
                    HStack {
                        Text(entry.method).font(.caption2.weight(.bold))
                            .foregroundStyle(entry.status < 400 ? .green : .red)
                        Text(perf.endpointName(for: entry)).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.durationMs)) ms").font(.caption2.monospacedDigit())
                        if entry.fromCache {
                            Image(systemName: "internaldrive").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Réseau")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Effacer") { perf.clear() }
            }
        }
    }
}
