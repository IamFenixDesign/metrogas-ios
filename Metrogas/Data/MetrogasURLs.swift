import Foundation

enum MetrogasURLs {
    static let oficinaVirtual = URL(string: "https://registro.micuenta.metrogas.com.ar/")!
    static let portalMobile = URL(string: "https://portal.micuenta.metrogas.com.ar/sites/ovmetrogasmobile")!
    static let portalOV2 = URL(string: "https://portal.micuenta.metrogas.com.ar/sites/ovmetrogas2")!
    static let acceso = URL(string: "https://acceso.micuenta.metrogas.com.ar/")!
    static let accesoOV2 = URL(string: "https://acceso.micuenta.metrogas.com.ar/sites/ovmetrogas2")!
    static let portalDesktop = URL(string: "https://portal.micuenta.metrogas.com.ar/")!
    static let registro = URL(string: "https://registro.micuenta.metrogas.com.ar/indexUserReg.html")!
    static let sitioInstitucional = URL(string: "https://www.metrogas.com.ar/")!

    /// Entrada de login igual que la web: portal → authn MDS → IdP SAP Identity.
    static let loginEntry = portalMobile

    /// Endpoint SAML SSO de SAP Identity (Acceso Mi Cuenta / MetroGAS).
    static let idpSSO = URL(string: "https://asskova9q.accounts.ondemand.com/saml2/idp/sso/asskova9q.accounts.ondemand.com")!
    static let idpHost = "asskova9q.accounts.ondemand.com"

    /// App pública “Tu Factura / Saldos” (OvServiceHub M360 real).
    static let saldos = URL(string: "https://saldos.micuenta.metrogas.com.ar/")!

    /// Deep link que dispara consulta de deuda/facturas para un N° de cliente (11 dígitos).
    static func saldosGo(accountId: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/index.html#/go/\(accountId)")!
    }

    static let m360InvoiceList = URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicinvoice/listR2")!
    static let m360Billing = URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicbilling/r2")!

    static func m360Consumption(accountId: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicinvoice/consumption/\(accountId)")!
    }

    static func m360Payments(accountId: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicpayment/list/\(accountId)")!
    }

    /// Factura digital / email adherido (captcha en el path).
    static func m360Subscription(accountId: String, captchaToken: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/publicSubscription/\(accountId)/\(captchaToken)")!
    }

    static func isMetrogasAuthHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("accounts.ondemand.com")
            || h.contains(idpHost)
            || h.contains("authn.br1.hana.ondemand.com")
            || h.contains("login.microsoftonline.com")
            || h.contains("accounts.google.com")
    }

    /// Página de login IdP (Acceso Mi Cuenta), no el portal aún autenticado.
    static func isIdentityLoginHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("accounts.ondemand.com")
            || h.contains(idpHost)
            || h.contains("authn.br1.hana.ondemand.com")
    }

    static func isMetrogasPortalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("portal.micuenta.metrogas.com.ar")
            || h.contains("acceso.micuenta.metrogas.com.ar")
            || h.contains("saldos.micuenta.metrogas.com.ar")
            || h.contains("dispatcher.br1.hana.ondemand.com")
            || h.contains("micuenta.metrogas.com.ar")
    }

    /// Hosts donde vive la sesión autenticada (OV). No incluye saldos (app pública).
    static func isAuthenticatedSessionHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("portal.micuenta.metrogas.com.ar")
            || h.contains("acceso.micuenta.metrogas.com.ar")
    }

    /// N° de cliente MetroGAS: 11 dígitos (como exige la web de saldos).
    static func normalizedCustomerNumber(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 11 else { return nil }
        return digits
    }
}
