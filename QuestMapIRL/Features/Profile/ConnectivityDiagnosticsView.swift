import SwiftUI
import UIKit

/// Resultado de probar un servicio.
struct ProbeResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let ok: Bool
    let detail: String
    let milliseconds: Int
}

/// Pruebas de conexión contra cada servicio que usa la app. Usan puntos FIJOS de Madrid: nunca se
/// envía la ubicación del usuario. Sin reintentos, para ver el comportamiento real de cada servicio.
@MainActor
@Observable
final class ConnectivityProbe {
    private(set) var results: [ProbeResult] = []
    private(set) var isRunning = false

    private let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) { self.diagnostics = diagnostics }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        let noRetry = RetryPolicy(maxRetries: 0)

        // 1) Plantilla de tiles del mapa
        var tileTemplate: String?
        await probe("Mapa (TileJSON)", service: "probe-tilejson", url: MapProviderConfig.openFreeMap.tilesURL,
                    timeout: 10, retry: noRetry) { data in
            let template = try TilePOISearchService.parseTileJSON(data)
            tileTemplate = template.url
            return "plantilla de tiles leída"
        }
        // 2) Un tile de Madrid
        if let template = tileTemplate {
            let url = template.replacingOccurrences(of: "{z}", with: "14")
                .replacingOccurrences(of: "{x}", with: "8023").replacingOccurrences(of: "{y}", with: "6177")
            await probe("Mapa (un tile de Madrid)", service: "probe-tile", url: url, timeout: 15, retry: noRetry) { data in
                let list = try MVTPOIDecoder.decode(data, z: 14, x: 8023, y: 6177)
                return "\(data.count / 1024) KB, \(list.count) puntos de interés"
            }
        }
        // 3) Buscador de direcciones
        await probe("Búsqueda (Photon)", service: "probe-photon",
                    url: ServiceEndpoints.default.geocoder.absoluteString + "?q=Madrid&limit=1", timeout: 10, retry: noRetry) { data in
            let places = try PhotonSearchService.parse(data)
            return "\(places.count) resultado(s)"
        }
        // 4) Rutas
        await probe("Rutas (OSRM)", service: "probe-osrm",
                    url: ServiceEndpoints.default.drivingRoute.absoluteString
                        + "-3.7038,40.4168;-3.6883,40.4530?overview=false&steps=false", timeout: 15, retry: noRetry) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["code"] as? String == "Ok" else { throw SearchError.decoding }
            return "ruta calculada"
        }
        isRunning = false
    }

    private func probe(_ name: String, service: String, url: String, timeout: TimeInterval, retry: RetryPolicy,
                       interpret: (Data) throws -> String) async {
        let started = Date()
        guard let url = URL(string: url) else {
            results.append(ProbeResult(name: name, ok: false, detail: "URL no válida", milliseconds: 0))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let client = ServiceClient(service: service, retry: retry, diagnostics: diagnostics)
        do {
            let data = try await client.data(for: request, operation: "probe")
            let detail = try interpret(data)
            results.append(ProbeResult(name: name, ok: true, detail: detail, milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
        } catch let error as SearchError {
            results.append(ProbeResult(name: name, ok: false, detail: "fallo: \(error.kind)", milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
        } catch is CancellationError {
            results.append(ProbeResult(name: name, ok: false, detail: "cancelada", milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
        } catch {
            results.append(ProbeResult(name: name, ok: false, detail: "respuesta no válida", milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
        }
    }
}

struct ConnectivityDiagnosticsView: View {
    let environment: AppEnvironment
    @State private var probe = ConnectivityProbe()
    @State private var events: [DiagnosticEvent] = DiagnosticsLog.shared.events

    private var header: [String] {
        let device = UIDevice.current
        return [
            "App: \(AppConfig.appName) \(AppConfig.version) (\(AppConfig.build))",
            "iOS: \(device.systemVersion), \(device.model)",
            "Red (NWPathMonitor): \(environment.network.pathDescription)",
            "Ubicación: \(environment.locationService.diagnosticSummary)",
            "Aviso de «sin conexión» visible: \(environment.network.showsOfflineNotice ? "sí" : "no")",
            "Pruebas ahora: " + (probe.results.isEmpty ? "(sin ejecutar)"
                : probe.results.map { "\($0.name)=\($0.ok ? "ok" : "FALLO") \($0.detail) \($0.milliseconds)ms" }.joined(separator: "; ")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Comprueba qué servicio falla y por qué, y el estado de la ubicación. Las pruebas usan puntos fijos de Madrid: no se envía tu ubicación ni tus búsquedas. El informe no contiene coordenadas, textos de búsqueda ni claves.")
                    .font(.footnote).foregroundStyle(AppColor.textSecondary)

                SettingsGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Red del sistema").font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                        Text(environment.network.pathDescription).font(.footnote).foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await probe.run(); events = DiagnosticsLog.shared.events }
                } label: {
                    HStack {
                        if probe.isRunning { ProgressView() }
                        Text(probe.isRunning ? "Probando…" : "Probar conexión").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(AppColor.textPrimary)
                }
                .disabled(probe.isRunning)

                if !probe.results.isEmpty {
                    SettingsGroup {
                        ForEach(Array(probe.results.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { RowDivider() }
                            HStack(spacing: 12) {
                                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(result.ok ? Color.green : Color.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                                    Text("\(result.detail) · \(result.milliseconds) ms").font(.caption).foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                        }
                    }
                }

                ShareLink(item: DiagnosticsLog.shared.report(header: header)) {
                    Label("Compartir informe", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AppColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(AppColor.textPrimary)
                }

                Text("Últimos eventos de red (\(events.count))").font(.headline).foregroundStyle(AppColor.textPrimary)
                if events.isEmpty {
                    Text("Todavía no hay eventos.").font(.footnote).foregroundStyle(AppColor.textSecondary)
                }
                ForEach(Array(events.suffix(25).reversed().enumerated()), id: \.offset) { _, event in
                    Text(event.summary)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(event.outcome == "error" ? Color.orange : AppColor.textSecondary)
                }

                Button("Borrar registro", role: .destructive) {
                    DiagnosticsLog.shared.clear()
                    events = []
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { events = DiagnosticsLog.shared.events }
    }
}
