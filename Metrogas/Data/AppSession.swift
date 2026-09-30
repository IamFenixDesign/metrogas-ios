import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    enum LoginMethod: String {
        case customerNumber
        case google
        case password
    }

    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.authenticated) }
    }
    @Published var appearanceMode: AppearanceMode = .system
    /// N° de cliente con el que se ingresó (11 dígitos).
    @Published var customerNumber: String? {
        didSet { UserDefaults.standard.set(customerNumber, forKey: Keys.customerNumber) }
    }
    @Published var loginEmail: String? {
        didSet { UserDefaults.standard.set(loginEmail, forKey: Keys.loginEmail) }
    }
    @Published var lastLoginMethod: LoginMethod? {
        didSet { UserDefaults.standard.set(lastLoginMethod?.rawValue, forKey: Keys.loginMethod) }
    }

    @Published var showGoogleAuth = false
    @Published var googleAuthURL: URL?
    @Published var isLoggingIn = false
    @Published var loginError: String?
    @Published var isConfirmingGoogleSession = false

    /// Snapshot cargado en el login por N° (evita un segundo fetch al entrar).
    private(set) var pendingLoginSnapshot: MetrogasDataSnapshot?

    private var googleFlowActive = false
    private var googleCompletionStarted = false
    private var didBootstrapSession = false

    var rememberedCustomerNumber: String? {
        MetrogasURLs.normalizedCustomerNumber(customerNumber ?? "")
    }

    var canContinueWithCustomerNumber: Bool {
        lastLoginMethod == .customerNumber && rememberedCustomerNumber != nil
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
        static let customerNumber = "metrogas.session.customerNumber"
    }

    init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Keys.authenticated)
        loginEmail = UserDefaults.standard.string(forKey: Keys.loginEmail)
        customerNumber = UserDefaults.standard.string(forKey: Keys.customerNumber)
            .flatMap { MetrogasURLs.normalizedCustomerNumber($0) }
        if let raw = UserDefaults.standard.string(forKey: Keys.loginMethod),
           let method = LoginMethod(rawValue: raw) {
            lastLoginMethod = method
        }
        // Migración: sesión vieja sin método → si hay N° guardado, tratarla como customerNumber.
        if isAuthenticated, lastLoginMethod == nil, rememberedCustomerNumber != nil {
            lastLoginMethod = .customerNumber
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.appearance),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }
    }

    /// Login principal: N° de cliente MetroGAS (11 dígitos) → datos reales de saldos/M360.
    func loginWithCustomerNumber(_ raw: String) async {
        guard let id = MetrogasURLs.normalizedCustomerNumber(raw) else {
            loginError = "Ingresá el N° de cliente de 11 dígitos (como figura en tu factura)."
            return
        }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            let snapshot = try await MetrogasDataService.shared.fetchByCustomerNumber(id)
            let profile = snapshot.account
            let hasSignal = !profile.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (!profile.supplyAddress.isEmpty && profile.supplyAddress != "—")
                || (!profile.meterNumber.isEmpty && profile.meterNumber != "—")
                || !snapshot.invoices.isEmpty
            guard hasSignal else {
                loginError = "No encontramos datos para ese N° de cliente. Revisalo e intentá de nuevo."
                return
            }

            customerNumber = id
            loginEmail = snapshot.account.email.isEmpty ? nil : snapshot.account.email
            lastLoginMethod = .customerNumber
            pendingLoginSnapshot = snapshot
            LinkedAccountStore.bindCustomerOnly(id)
            CredentialStore.clear()
            didBootstrapSession = true
            isAuthenticated = true
        } catch {
            loginError = "No pudimos consultar MetroGAS. Revisá el N° y tu conexión."
        }
    }

    func continueWithSavedCustomerNumber() async {
        guard let id = rememberedCustomerNumber else {
            loginError = "Ingresá tu N° de cliente."
            return
        }
        await loginWithCustomerNumber(id)
    }

    func useAnotherAccount() {
        lastLoginMethod = nil
        customerNumber = nil
        loginEmail = nil
        loginError = nil
        pendingLoginSnapshot = nil
        CredentialStore.clear()
        LinkedAccountStore.clearAllBindings()
    }

    func consumePendingLoginSnapshot() -> MetrogasDataSnapshot? {
        let snap = pendingLoginSnapshot
        pendingLoginSnapshot = nil
        return snap
    }

    @discardableResult
    func restoreSessionIfNeeded() async -> Bool {
        guard isAuthenticated else { return false }

        if lastLoginMethod == .customerNumber || rememberedCustomerNumber != nil {
            // Login por N°: no hace falta sesión SAP/Google.
            if rememberedCustomerNumber == nil {
                await forceLocalLogout(keepCustomerNumber: false)
                return false
            }
            lastLoginMethod = .customerNumber
            didBootstrapSession = true
            return true
        }

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
            await forceLocalLogout(keepCustomerNumber: true)
            return false
        } catch MetrogasAuthError.sessionExpired, MetrogasAuthError.invalidCredentials {
            CredentialStore.clear()
            await forceLocalLogout(keepCustomerNumber: true)
            loginError = "Tu sesión venció. Volvé a ingresar con tu N° de cliente."
            return false
        } catch {
            didBootstrapSession = true
            return true
        }
    }

    func logout() async {
        isAuthenticated = false
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
        loginError = nil
        pendingLoginSnapshot = nil
        // Recordar N° para “Continuar” rápido.
        let preservedNumber = rememberedCustomerNumber
        let keepNumber = lastLoginMethod == .customerNumber && preservedNumber != nil
        CredentialStore.clear()
        await MetrogasAuthService.shared.clearCookies()
        await WebCookieBridge.clearWebKitData()
        if keepNumber {
            customerNumber = preservedNumber
            lastLoginMethod = .customerNumber
            loginEmail = nil
        } else {
            customerNumber = nil
            lastLoginMethod = nil
            loginEmail = nil
        }
    }

    func expireSession(clearSavedPassword: Bool) async {
        if clearSavedPassword { CredentialStore.clear() }
        // Con login por N° no hay sesión SAP que expire: reingresar con el mismo N°.
        if lastLoginMethod == .customerNumber {
            loginError = "Volvé a ingresar con tu N° de cliente."
        } else {
            loginError = MetrogasAuthError.sessionExpired.errorDescription
        }
        await forceLocalLogout(keepCustomerNumber: true)
        await MetrogasAuthService.shared.clearCookies()
        await WebCookieBridge.clearWebKitData()
    }

    private func forceLocalLogout(keepCustomerNumber: Bool) async {
        let preservedNumber = keepCustomerNumber ? rememberedCustomerNumber : nil
        let preservedMethod: LoginMethod? = keepCustomerNumber && preservedNumber != nil ? .customerNumber : nil
        isAuthenticated = false
        customerNumber = preservedNumber
        lastLoginMethod = preservedMethod
        loginEmail = keepCustomerNumber ? loginEmail : nil
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        didBootstrapSession = false
        pendingLoginSnapshot = nil
    }

    func persistAppearance() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
    }

    // MARK: - Compat stubs (UI vieja / sheets)

    var canContinueWithGoogle: Bool { false }
    var rememberedGoogleEmail: String? { nil }

    func login(email: String, password: String) async {
        _ = email
        _ = password
        loginError = "Ingresá con tu N° de cliente MetroGAS."
    }

    func startGoogleLogin() async {
        loginError = "Ingresá con tu N° de cliente MetroGAS."
    }

    func continueWithSavedGoogleAccount() async {
        await continueWithSavedCustomerNumber()
    }

    func handleGoogleAuthNavigation(_ url: URL) {
        _ = url
    }

    func cancelGoogleLogin() {
        showGoogleAuth = false
        googleAuthURL = nil
        googleFlowActive = false
        isConfirmingGoogleSession = false
        isLoggingIn = false
    }
}
