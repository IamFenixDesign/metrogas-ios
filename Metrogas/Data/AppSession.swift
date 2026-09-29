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

    /// Portal post-login (facturas / consumo / cuenta).
    @Published var showLoginPortal = false
    @Published var portalStartURL: URL = MetrogasURLs.portalMobile
    @Published private(set) var lastPortalURL: URL?

    /// Sheet de registro (sigue siendo la web oficial).
    @Published var showRegistrationPortal = false

    /// Sheet que abre únicamente accounts.google.com.
    @Published var showGoogleAuth = false
    @Published var googleAuthURL: URL?

    @Published var isLoggingIn = false
    @Published var loginError: String?

    private var googleFlowActive = false

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

    // MARK: - Native login

    func login(email: String, password: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            loginError = "Ingresá tu email y contraseña."
            return
        }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            try await MetrogasAuthService.shared.login(email: trimmed, password: password)
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
            isAuthenticated = true
        } catch let error as MetrogasAuthError {
            loginError = error.errorDescription
        } catch {
            loginError = "No pudimos iniciar sesión. Revisá tu conexión e intentá de nuevo."
        }
    }

    func startGoogleLogin() async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            let url = try await MetrogasAuthService.shared.prepareGoogleOAuthURL()
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
            googleAuthURL = url
            googleFlowActive = true
            showGoogleAuth = true
        } catch let error as MetrogasAuthError {
            loginError = error.errorDescription
        } catch {
            loginError = "No pudimos abrir el inicio de sesión con Google."
        }
    }

    func handleGoogleAuthNavigation(_ url: URL) {
        lastPortalURL = url
        guard googleFlowActive, let host = url.host?.lowercased() else { return }

        // Éxito: Google → SAP → portal MetroGAS.
        if MetrogasURLs.isMetrogasPortalHost(host) {
            Task {
                await WebCookieBridge.syncWebKitCookiesToHTTP()
                googleFlowActive = false
                showGoogleAuth = false
                googleAuthURL = nil
                isAuthenticated = true
            }
        }
    }

    func cancelGoogleLogin() {
        googleFlowActive = false
        showGoogleAuth = false
        googleAuthURL = nil
        loginError = nil
    }

    func beginRegistration() {
        portalStartURL = MetrogasURLs.registro
        showRegistrationPortal = true
    }

    func openPortal(at url: URL = MetrogasURLs.portalMobile) {
        portalStartURL = url
        showLoginPortal = true
    }

    func handlePortalNavigation(_ url: URL) {
        lastPortalURL = url
    }

    func logout() async {
        isAuthenticated = false
        lastPortalURL = nil
        showLoginPortal = false
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        loginError = nil

        await MetrogasAuthService.shared.clearCookies()
        await WebCookieBridge.clearWebKitData()
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }
}
