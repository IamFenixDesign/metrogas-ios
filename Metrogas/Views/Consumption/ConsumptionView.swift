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
            .toolbarBackground(.hidden, for: .navigationBar)
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
                title: "Bimestres",
                value: "\(store.visibleReadings.count)",
                icon: "calendar",
                accent: MetrogasTheme.brandFlame
            )
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Consumos",
                subtitle: "Actual vs mismo bimestre del año anterior (como en MetroGAS)"
            )

            if store.visibleReadings.isEmpty {
                Text(
                    store.isLoading
                        ? "Cargando consumo…"
                        : "No hay información de consumo"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                Chart {
                    ForEach(store.visibleReadings) { reading in
                        BarMark(
                            x: .value("Período", reading.chartLabel),
                            y: .value("m³", reading.cubicMeters)
                        )
                        .foregroundStyle(by: .value("Serie", "Actual"))
                        .position(by: .value("Serie", "Actual"))
                        .cornerRadius(6)

                        if reading.previousYearCubicMeters > 0 {
                            BarMark(
                                x: .value("Período", reading.chartLabel),
                                y: .value("m³", reading.previousYearCubicMeters)
                            )
                            .foregroundStyle(by: .value("Serie", "Anterior"))
                            .position(by: .value("Serie", "Anterior"))
                            .cornerRadius(6)
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Actual": MetrogasTheme.brandBlue,
                    "Anterior": MetrogasTheme.brandFlame.opacity(0.85)
                ])
                .chartLegend(position: .top, alignment: .trailing)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 240)
                .animation(MetrogasTheme.springSoft, value: store.consumptionPeriod)
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 22, prominent: true)
    }

    private var comparisonCard: some View {
        Group {
            if let latest = store.visibleReadings.last {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: "Último bimestre",
                        subtitle: latest.fullPeriodLabel
                    )

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Actual")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MetrogasTheme.brandBlue)
                            Text(Formatters.m3(latest.cubicMeters))
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }

                        if latest.previousYearCubicMeters > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anterior")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MetrogasTheme.brandFlame)
                                Text(Formatters.m3(latest.previousYearCubicMeters))
                                    .font(.title3.weight(.semibold).monospacedDigit())
                            }

                            Spacer()

                            Text(Formatters.signedPercent(latest.comparedToPreviousPercent))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(
                                    latest.comparedToPreviousPercent > 0
                                        ? MetrogasTheme.danger
                                        : MetrogasTheme.success
                                )
                                .contentTransition(.numericText())
                        } else {
                            Spacer()
                        }
                    }

                    if latest.previousYearCubicMeters > 0 {
                        Text(yearOverYearCopy(latest))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .liquidGlass(cornerRadius: 22)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Detalle por período", subtitle: "Consumo facturado (m³)")

            if store.visibleReadings.isEmpty {
                Text("Cuando MetroGAS tenga lecturas, van a aparecer acá.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 18)
            } else {
                ForEach(Array(store.visibleReadings.reversed().enumerated()), id: \.element.id) { index, reading in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.fullPeriodLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("Prom. diario \(Formatters.m3(reading.averageDaily))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Formatters.m3(reading.cubicMeters))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                            if reading.previousYearCubicMeters > 0 {
                                Text("Ant. \(Formatters.m3(reading.previousYearCubicMeters))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(Formatters.signedPercent(reading.comparedToPreviousPercent))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(
                                        reading.comparedToPreviousPercent >= 0
                                            ? MetrogasTheme.danger
                                            : MetrogasTheme.success
                                    )
                            }
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 16)
                    .appearMotion(visible: appear, index: min(index + 5, 10))
                }
            }
        }
    }

    private func yearOverYearCopy(_ latest: ConsumptionReading) -> String {
        let delta = latest.cubicMeters - latest.previousYearCubicMeters
        if delta > 0 {
            return "Consumiste \(Formatters.m3(delta)) más que en el mismo bimestre del año anterior."
        }
        if delta < 0 {
            return "Consumiste \(Formatters.m3(abs(delta))) menos que en el mismo bimestre del año anterior."
        }
        return "El consumo fue igual al mismo bimestre del año anterior."
    }
}
