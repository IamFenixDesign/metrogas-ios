import Foundation
import SwiftUI
import WebKit
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.authenticated) }
    }
    @Published var appearanceMode: AppearanceMode = .system
    @Published var showLoginPortal = false
    @Published var portalStartURL: URL = MetrogasURLs.portalMobile
    @Published private(set) var lastPortalURL: URL?

    /// True once the user hits SAP Identity / SAML during the current login attempt.
    private var sawIdentityProvider = false

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "Sistema"
        case light = "Claro"
        case dark = "Oscuro"
        var id: String { rawValue }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private enum Keys {
        static let authenticated = "metrogas.session.authenticated"
        static let appearance = "metrogas.session.appearance"
    }

    init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Keys.authenticated)
        if let raw = UserDefaults.standard.string(forKey: Keys.appearance),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }
    }

    func beginLogin() {
        sawIdentityProvider = false
        portalStartURL = MetrogasURLs.portalMobile
        showLoginPortal = true
    }

    func beginRegistration() {
        sawIdentityProvider = false
        portalStartURL = MetrogasURLs.registro
        showLoginPortal = true
    }

    func openPortal(at url: URL = MetrogasURLs.portalMobile) {
        portalStartURL = url
        showLoginPortal = true
    }

    func handlePortalNavigation(_ url: URL) {
        lastPortalURL = url
        guard let host = url.host?.lowercased() else { return }

        if MetrogasURLs.isMetrogasAuthHost(host) {
            sawIdentityProvider = true
            return
        }

        // Tras pasar por el IdP de MetroGAS/SAP y volver al portal, consideramos sesión real.
        if sawIdentityProvider && MetrogasURLs.isMetrogasPortalHost(host) {
            isAuthenticated = true
        }

        // Si ya estábamos autenticados y volvemos al portal, mantenemos sesión.
        if isAuthenticated && MetrogasURLs.isMetrogasPortalHost(host) {
            isAuthenticated = true
        }
    }

    func confirmLoggedInManually() {
        isAuthenticated = true
        showLoginPortal = false
    }

    func logout() async {
        isAuthenticated = false
        sawIdentityProvider = false
        lastPortalURL = nil
        showLoginPortal = false

        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let metrogasRecords = records.filter { record in
            record.displayName.lowercased().contains("metrogas")
                || record.displayName.lowercased().contains("ondemand.com")
                || record.displayName.lowercased().contains("hana.ondemand")
        }
        if !metrogasRecords.isEmpty {
            await dataStore.removeData(ofTypes: types, for: metrogasRecords)
        } else {
            // Fallback: clear all web data for a clean session.
            await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        }
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }
}
