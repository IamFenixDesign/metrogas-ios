import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.authenticated) }
    }
    @Published var appearanceMode: AppearanceMode = .system
    @Published var loginEmail: String? {
        didSet { UserDefaults.standard.set(loginEmail, forKey: Keys.loginEmail) }
    }

    /// Sheet que abre únicamente accounts.google.com.
    @Published var showGoogleAuth = false
    @Published var googleAuthURL: URL?

    @Published var isLoggingIn = false
    @Published var loginError: String?
    @Published var isRestoringSession = false

    private var googleFlowActive = false
    private var didBootstrapSession = false

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
        static let loginEmail = "metrogas.session.loginEmail"
    }

    init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Keys.authenticated)
        loginEmail = UserDefaults.standard.string(forKey: Keys.loginEmail)
        if let raw = UserDefaults.standard.string(forKey: Keys.appearance),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }
    }

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
            CredentialStore.save(email: trimmed, password: password)
            loginEmail = trimmed
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
            didBootstrapSession = true
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
        guard googleFlowActive, let host = url.host?.lowercased() else { return }

        if MetrogasURLs.isMetrogasPortalHost(host) {
            Task {
                await WebCookieBridge.syncWebKitCookiesToHTTP()
                googleFlowActive = false
                showGoogleAuth = false
                googleAuthURL = nil
                didBootstrapSession = true
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

    /// Al abrir la app con sesión ya marcada: restaura cookies, revalida y deja lista la sync.
    /// Devuelve `true` si la sesión quedó usable para sincronizar datos.
    @discardableResult
    func restoreSessionIfNeeded() async -> Bool {
        guard isAuthenticated else { return false }
        if didBootstrapSession {
            // Igual revalidamos por si las cookies vencieron en background.
        }

        isRestoringSession = true
        defer { isRestoringSession = false }

        // 1) Cookies de un login Google previo pueden estar en WK.
        await WebCookieBridge.syncWebKitCookiesToHTTP()

        let saved = CredentialStore.load()
        let email = saved?.email ?? loginEmail
        let password = saved?.password

        do {
            let ok = try await MetrogasAuthService.shared.ensureActiveSession(
                email: email,
                password: password
            )
            if ok {
                if let email { loginEmail = email }
                let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
                await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
                didBootstrapSession = true
                return true
            }
            await forceLocalLogout()
            return false
        } catch MetrogasAuthError.sessionExpired {
            await forceLocalLogout(keepEmail: true)
            loginError = MetrogasAuthError.sessionExpired.errorDescription
            return false
        } catch MetrogasAuthError.invalidCredentials {
            CredentialStore.clear()
            await forceLocalLogout(keepEmail: true)
            loginError = "Tu sesión venció. Volvé a ingresar."
            return false
        } catch {
            // Red caída: mantenemos la sesión local y dejamos que sync muestre el error.
            didBootstrapSession = true
            return true
        }
    }

    func logout() async {
        await forceLocalLogout(keepEmail: false)
        CredentialStore.clear()
        await MetrogasAuthService.shared.clearCookies()
        await WebCookieBridge.clearWebKitData()
    }

    /// Sesión SAP vencida: limpia cookies pero deja el email para reingresar rápido.
    func expireSession(clearSavedPassword: Bool) async {
        if clearSavedPassword { CredentialStore.clear() }
        await forceLocalLogout(keepEmail: true)
        await MetrogasAuthService.shared.clearCookies()
        await WebCookieBridge.clearWebKitData()
        loginError = MetrogasAuthError.sessionExpired.errorDescription
    }

    private func forceLocalLogout(keepEmail: Bool) async {
        let preserved = keepEmail ? loginEmail : nil
        isAuthenticated = false
        loginEmail = preserved
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }
}
