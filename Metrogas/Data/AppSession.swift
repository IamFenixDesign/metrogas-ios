import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    enum LoginMethod: String {
        case google
        case password
        case web
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

    /// Sheet con el mismo login web (portal → IdP asskova9q / Google).
    @Published var showWebLogin = false
    @Published var webLoginURL: URL?

    @Published var isLoggingIn = false
    @Published var loginError: String?
    /// El WebView volvió al portal y estamos confirmando la sesión SAP.
    @Published var isConfirmingWebSession = false

    private var webLoginActive = false
    private var webLoginCompletionStarted = false
    private var webLoginSawGoogle = false
    /// True cuando el WebView ya pasó por el IdP SAP (Acceso Mi Cuenta).
    private var webLoginSawIdP = false
    private var didBootstrapSession = false

    private var loginHintMissing: Bool {
        guard let loginEmail else { return true }
        return loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Cuenta recordada: se puede continuar sin volver a elegir proveedor.
    var canContinueWithSavedAccount: Bool {
        (lastLoginMethod == .google || lastLoginMethod == .web || lastLoginMethod == .password)
            && !loginHintMissing
    }

    /// Compat con pantallas que aún consultan el nombre viejo.
    var canContinueWithGoogle: Bool { canContinueWithSavedAccount }

    var rememberedAccountEmail: String? {
        guard canContinueWithSavedAccount else { return nil }
        return loginEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var rememberedGoogleEmail: String? { rememberedAccountEmail }

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

    /// Abre el mismo inicio de sesión que la web: portal → MDS → IdP SAP.
    func startWebLogin() async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        await WebCookieBridge.syncWebKitCookiesToHTTP()
        let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
        await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)

        webLoginURL = MetrogasURLs.loginEntry
        webLoginActive = true
        webLoginCompletionStarted = false
        webLoginSawGoogle = false
        webLoginSawIdP = false
        isConfirmingWebSession = false
        showWebLogin = true
    }

    /// Continúa con la cuenta recordada: sesión viva o mismo login web.
    func continueWithSavedAccount() async {
        guard canContinueWithSavedAccount else {
            await startWebLogin()
            return
        }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        await WebCookieBridge.syncWebKitCookiesToHTTP()

        if await MetrogasAuthService.shared.probePortalSession() {
            let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
            if let email = identity.email, !email.isEmpty {
                loginEmail = email
            }
            lastLoginMethod = lastLoginMethod ?? .web
            let cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
            await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
            didBootstrapSession = true
            isAuthenticated = true
            return
        }

        // Reabrir el mismo IdP web; con cookies suele completar solo.
        webLoginURL = MetrogasURLs.loginEntry
        webLoginActive = true
        webLoginCompletionStarted = false
        webLoginSawGoogle = lastLoginMethod == .google
        webLoginSawIdP = false
        isConfirmingWebSession = false
        showWebLogin = true
    }

    func continueWithSavedGoogleAccount() async {
        await continueWithSavedAccount()
    }

    /// Olvida la cuenta recordada y vuelve a la pantalla de ingreso.
    func useAnotherAccount() {
        lastLoginMethod = nil
        loginEmail = nil
        loginError = nil
        CredentialStore.clear()
    }

    /// Compat: mismos puntos de entrada que antes, ahora usan el IdP web.
    func startGoogleLogin() async {
        await startWebLogin()
    }

    func login(email: String, password: String) async {
        // El ingreso nativo también arranca el IdP web (mismo flujo que la OV).
        _ = email
        _ = password
        await startWebLogin()
    }

    func handleWebLoginNavigation(_ url: URL) {
        guard webLoginActive, let host = url.host?.lowercased() else { return }

        if host.contains("accounts.google.com") || host.contains("google.com") {
            webLoginSawGoogle = true
            if let email = MetrogasAuthService.emailFromOAuthURL(url) {
                loginEmail = email
            }
            return
        }

        // IdP / authn: el usuario está en Acceso Mi Cuenta (mismo inicio que la web).
        if MetrogasURLs.isIdentityLoginHost(host) {
            webLoginSawIdP = true
            return
        }

        // Solo portal/acceso. Ignorar saldos (app pública) y el bounce inicial ?hc_login
        // hasta haber pasado por el IdP (salvo sesión ya viva).
        guard MetrogasURLs.isAuthenticatedSessionHost(host) else { return }
        let isLoginBounce = (url.query ?? "").contains("hc_login")
        if isLoginBounce && !webLoginSawIdP && !webLoginSawGoogle {
            return
        }
        guard !webLoginCompletionStarted else { return }

        // Primer hit al portal sin IdP: solo completar si la sesión ya está viva.
        if !webLoginSawIdP && !webLoginSawGoogle {
            webLoginCompletionStarted = true
            Task {
                await WebCookieBridge.syncWebKitCookiesToHTTP()
                if webLoginActive, await MetrogasAuthService.shared.probePortalSession() {
                    await finishWebLogin(method: lastLoginMethod ?? .web)
                } else {
                    webLoginCompletionStarted = false
                }
            }
            return
        }

        webLoginCompletionStarted = true
        isConfirmingWebSession = true
        isLoggingIn = true

        Task {
            defer {
                isConfirmingWebSession = false
                isLoggingIn = false
            }

            var sessionReady = false
            for _ in 0..<24 {
                guard webLoginActive else { return }
                await WebCookieBridge.syncWebKitCookiesToHTTP()
                if await MetrogasAuthService.shared.probePortalSession() {
                    sessionReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            guard webLoginActive else { return }

            guard sessionReady else {
                webLoginCompletionStarted = false
                webLoginActive = false
                showWebLogin = false
                webLoginURL = nil
                loginError = "No pudimos confirmar la sesión de MetroGAS. Intentá de nuevo."
                return
            }

            await finishWebLogin(method: webLoginSawGoogle ? .google : .web)
        }
    }

    private func finishWebLogin(method: LoginMethod) async {
        // Asegurar cookies WK ↔ HTTP antes del sync (crítico con Google).
        await WebCookieBridge.syncWebKitCookiesToHTTP()
        var cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
        await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)

        var resolvedEmail = loginEmail
        for _ in 0..<12 {
            let identity = await MetrogasAuthService.shared.resolveSignedInIdentity()
            if let email = identity.email, !email.isEmpty {
                resolvedEmail = email
                break
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if let resolvedEmail {
            loginEmail = resolvedEmail
        }

        // Re-probe: tras Google el portal a veces tarda un poco más en quedar usable.
        for _ in 0..<8 {
            if await MetrogasAuthService.shared.probePortalSession() { break }
            await WebCookieBridge.syncWebKitCookiesToHTTP()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        lastLoginMethod = method
        webLoginActive = false
        showWebLogin = false
        webLoginURL = nil
        webLoginCompletionStarted = false
        webLoginSawIdP = false
        webLoginSawGoogle = false
        isConfirmingWebSession = false
        cookies = await MetrogasAuthService.shared.exportCookiesForWebKit()
        await WebCookieBridge.syncHTTPCookiesToWebKit(cookies)
        didBootstrapSession = true
        isAuthenticated = true
    }

    /// Alias usado por la sheet legacy.
    func handleGoogleAuthNavigation(_ url: URL) {
        handleWebLoginNavigation(url)
    }

    func cancelWebLogin() {
        webLoginActive = false
        webLoginCompletionStarted = false
        webLoginSawGoogle = false
        webLoginSawIdP = false
        isConfirmingWebSession = false
        showWebLogin = false
        webLoginURL = nil
        loginError = nil
        isLoggingIn = false
    }

    func cancelGoogleLogin() {
        cancelWebLogin()
    }

    /// Al abrir la app con sesión ya marcada: restaura cookies, revalida y deja lista la sync.
    @discardableResult
    func restoreSessionIfNeeded() async -> Bool {
        guard isAuthenticated else { return false }

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
            didBootstrapSession = true
            return true
        }
    }

    func logout() async {
        let keepAccount = (lastLoginMethod == .google || lastLoginMethod == .web) && !loginHintMissing
        let preservedEmail = keepAccount ? loginEmail : nil
        let preservedMethod: LoginMethod? = keepAccount ? lastLoginMethod : nil

        isAuthenticated = false
        showWebLogin = false
        webLoginURL = nil
        webLoginActive = false
        didBootstrapSession = false
        loginError = nil
        CredentialStore.clear()

        if keepAccount {
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

    func expireSession(clearSavedPassword: Bool) async {
        if clearSavedPassword { CredentialStore.clear() }
        let keepAccount = lastLoginMethod == .google || lastLoginMethod == .web
        let preserved = loginEmail
        isAuthenticated = false
        showWebLogin = false
        webLoginURL = nil
        webLoginActive = false
        didBootstrapSession = false
        loginEmail = preserved
        if keepAccount {
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
        showWebLogin = false
        webLoginURL = nil
        webLoginActive = false
        didBootstrapSession = false
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }
}
