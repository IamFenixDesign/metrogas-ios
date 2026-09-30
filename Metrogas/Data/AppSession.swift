import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    enum LoginMethod: String {
        case google
        case password
    }

    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.authenticated) }
    }
    @Published var appearanceMode: AppearanceMode = .system
    @Published var loginEmail: String? {
        didSet { UserDefaults.standard.set(loginEmail, forKey: Keys.loginEmail) }
    }
    @Published var lastLoginMethod: LoginMethod? {
        didSet { UserDefaults.standard.set(lastLoginMethod?.rawValue, forKey: Keys.loginMethod) }
    }

    /// Sheet que abre únicamente accounts.google.com.
    @Published var showGoogleAuth = false
    @Published var googleAuthURL: URL?

    @Published var isLoggingIn = false
    @Published var loginError: String?

    private var googleFlowActive = false
    private var didBootstrapSession = false

    private var loginHintMissing: Bool {
        guard let loginEmail else { return true }
        return loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Cuenta Google recordada: se puede continuar sin pedir email/contraseña.
    var canContinueWithGoogle: Bool {
        lastLoginMethod == .google && !loginHintMissing
    }

    var rememberedGoogleEmail: String? {
        guard canContinueWithGoogle else { return nil }
        return loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        static let loginMethod = "metrogas.session.loginMethod"
    }

    init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Keys.authenticated)
        loginEmail = UserDefaults.standard.string(forKey: Keys.loginEmail)
        if let raw = UserDefaults.standard.string(forKey: Keys.loginMethod),
           let method = LoginMethod(rawValue: raw) {
            lastLoginMethod = method
        }
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
            lastLoginMethod = .password
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

    /// Continúa con la cuenta Google recordada: sin pedir email ni contraseña.
    func continueWithSavedGoogleAccount() async {
        guard canContinueWithGoogle else {
            await startGoogleLogin()
            return
        }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        await WebCookieBridge.syncWebKitCookiesToHTTP()

        // Si la sesión del portal sigue viva, entrar directo.
        if await MetrogasAuthService.shared.probePortalSession() {
            let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
            if let email = identity.email, !email.isEmpty {
                loginEmail = email
            }
            if let customer = identity.customerNumber {
                LinkedAccountStore.bind(email: loginEmail, customerNumber: customer)
            }
            lastLoginMethod = .google
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
            didBootstrapSession = true
            isAuthenticated = true
            return
        }

        // Abrir Google OAuth: con cookies de Google suele bastar elegir la cuenta.
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
            loginError = "No pudimos continuar con tu cuenta de Google."
        }
    }

    /// Olvida la cuenta Google recordada y vuelve al formulario completo.
    func useAnotherAccount() {
        lastLoginMethod = nil
        loginEmail = nil
        loginError = nil
        CredentialStore.clear()
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

        // Capturar email desde la URL de Google apenas aparece (login_hint / Email).
        if host.contains("accounts.google.com") || host.contains("google.com") {
            if let email = MetrogasAuthService.emailFromOAuthURL(url) {
                loginEmail = email
            }
            return
        }

        if MetrogasURLs.isMetrogasPortalHost(host) {
            Task {
                await WebCookieBridge.syncWebKitCookiesToHTTP()
                // Siempre re-resolver identidad Google/SAP (no conservar un email viejo).
                var resolvedEmail = loginEmail
                var resolvedCustomer: String?
                for _ in 0..<6 {
                    let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
                    if let email = identity.email, !email.isEmpty {
                        resolvedEmail = email
                    }
                    if let customer = identity.customerNumber {
                        resolvedCustomer = customer
                    }
                    if resolvedEmail != nil { break }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                if let resolvedEmail {
                    loginEmail = resolvedEmail
                }
                if let resolvedCustomer {
                    LinkedAccountStore.bind(email: loginEmail, customerNumber: resolvedCustomer)
                }
                lastLoginMethod = .google
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
    /// No bloquea la UI: corre en background tras el splash corto.
    @discardableResult
    func restoreSessionIfNeeded() async -> Bool {
        guard isAuthenticated else { return false }

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
            await forceLocalLogout(keepEmail: true)
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
        let keepGoogleAccount = lastLoginMethod == .google && !loginHintMissing
        let preservedEmail = keepGoogleAccount ? loginEmail : nil
        let preservedMethod: LoginMethod? = keepGoogleAccount ? .google : nil

        isAuthenticated = false
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
        loginError = nil
        CredentialStore.clear()

        if keepGoogleAccount {
            // Mantener identidad Google + cookies de Google; cortar solo MetroGAS/SAP.
            loginEmail = preservedEmail
            lastLoginMethod = preservedMethod
            await MetrogasAuthService.shared.clearMetrogasSessionCookiesKeepingGoogle()
            await WebCookieBridge.clearNonGoogleWebKitData()
        } else {
            loginEmail = nil
            lastLoginMethod = nil
            await MetrogasAuthService.shared.clearCookies()
            await WebCookieBridge.clearWebKitData()
        }
    }

    /// Sesión SAP vencida: limpia cookies pero deja el email para reingresar rápido.
    func expireSession(clearSavedPassword: Bool) async {
        if clearSavedPassword { CredentialStore.clear() }
        let keepGoogle = lastLoginMethod == .google
        let preserved = loginEmail
        isAuthenticated = false
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
        loginEmail = preserved
        if keepGoogle {
            await MetrogasAuthService.shared.clearMetrogasSessionCookiesKeepingGoogle()
            await WebCookieBridge.clearNonGoogleWebKitData()
        } else {
            await MetrogasAuthService.shared.clearCookies()
            await WebCookieBridge.clearWebKitData()
        }
        loginError = MetrogasAuthError.sessionExpired.errorDescription
    }

    private func forceLocalLogout(keepEmail: Bool) async {
        let preserved = keepEmail ? loginEmail : nil
        let preservedMethod = keepEmail ? lastLoginMethod : nil
        isAuthenticated = false
        loginEmail = preserved
        lastLoginMethod = preservedMethod
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }
}
