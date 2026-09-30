import SwiftUI
import Charts

struct ConsumptionView: View {
    @EnvironmentObject private var store: AccountDataStore
    @EnvironmentObject private var tabScroll: TabBarScrollState
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TabBarScrollProbe()

                    periodPicker
                        .appearMotion(visible: appear, index: 0)
                    summaryRow
                        .appearMotion(visible: appear, index: 1)
                    chartCard
                        .appearMotion(visible: appear, index: 2)
                    comparisonCard
                        .appearMotion(visible: appear, index: 3)
                    historyList
                        .appearMotion(visible: appear, index: 4)

                    FloatingTabBarSpacer()
                }
                .padding(20)
            }
            .tracksFloatingTabBar(tabScroll)
            .background { LiquidGlassBackground() }
            .navigationTitle("Consumo")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                withAnimation(MetrogasTheme.springSoft) { appear = true }
            }
        }
    }

    private var periodPicker: some View {
        Picker("Período", selection: $store.consumptionPeriod) {
            ForEach(ConsumptionPeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .liquidGlass(cornerRadius: 16)
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Promedio",
                value: Formatters.m3(store.averageConsumption),
                icon: "chart.line.uptrend.xyaxis",
                accent: MetrogasTheme.brandBlue
            )
            MetricTile(
                title: "Períodos",
                value: "\(store.visibleReadings.count)",
                icon: "calendar",
                accent: MetrogasTheme.brandFlame
            )
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Historial de uso",
                subtitle: "Metros cúbicos por período de facturación"
            )

            if store.visibleReadings.isEmpty {
                Text(
                    store.isLoading
                        ? "Cargando consumo…"
                        : "No hay datos de consumo para el período elegido."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                Chart(store.visibleReadings) { reading in
                    BarMark(
                        x: .value("Mes", reading.monthLabel),
                        y: .value("m³", reading.cubicMeters)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MetrogasTheme.brandBlue, MetrogasTheme.brandCyan],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(8)

                    RuleMark(y: .value("Promedio", store.averageConsumption))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(MetrogasTheme.deepNavy.opacity(0.45))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Prom.")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
                .animation(MetrogasTheme.springSoft, value: store.consumptionPeriod)
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22, prominent: true)
    }

    private var comparisonCard: some View {
        Group {
            if let latest = store.visibleReadings.last,
               let previous = store.visibleReadings.dropLast().last {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Comparación de períodos")

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(previous.fullPeriodLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatters.m3(previous.cubicMeters))
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(latest.fullPeriodLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatters.m3(latest.cubicMeters))
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }

                        Spacer()

                        let delta = ((latest.cubicMeters - previous.cubicMeters) / previous.cubicMeters) * 100
                        Text(Formatters.signedPercent(delta))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(delta > 0 ? MetrogasTheme.danger : MetrogasTheme.success)
                            .contentTransition(.numericText())
                    }

                    Text(deltaCopy(latest: latest, previous: previous))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .liquidGlass(cornerRadius: 22)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Detalle mensual")

            if store.visibleReadings.isEmpty {
                Text("Cuando haya lecturas sincronizadas, van a aparecer acá.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 18)
            } else {
                ForEach(Array(store.visibleReadings.reversed().enumerated()), id: \.element.id) { index, reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.fullPeriodLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("Prom. diario \(Formatters.m3(reading.averageDaily))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Formatters.m3(reading.cubicMeters))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                            Text(Formatters.signedPercent(reading.comparedToPreviousPercent))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(
                                    reading.comparedToPreviousPercent >= 0
                                        ? MetrogasTheme.danger
                                        : MetrogasTheme.success
                                )
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 16)
                    .appearMotion(visible: appear, index: min(index + 5, 10))
                }
            }
        }
    }

    private func deltaCopy(latest: ConsumptionReading, previous: ConsumptionReading) -> String {
        let delta = latest.cubicMeters - previous.cubicMeters
        if delta > 0 {
            return "El último período consumió \(Formatters.m3(delta)) más que \(previous.fullPeriodLabel)."
        } else if delta < 0 {
            return "El último período ahorró \(Formatters.m3(abs(delta))) respecto de \(previous.fullPeriodLabel)."
        }
        return "El consumo se mantuvo igual entre ambos períodos."
    }
}
