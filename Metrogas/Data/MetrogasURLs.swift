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

    /// App pública “Tu Factura / Saldos” (OvServiceHub M360 real).
    static let saldos = URL(string: "https://saldos.micuenta.metrogas.com.ar/")!

    /// Deep link que dispara consulta de deuda/facturas para un N° de cliente (11 dígitos).
    static func saldosGo(accountId: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/index.html#/go/\(accountId)")!
    }

    /// Deep link de pago MetroGAS (tarjeta, código, MODO, Mercado Pago).
    static func saldosPagar(accountId: String) -> URL {
        URL(string: "https://saldos.micuenta.metrogas.com.ar/index.html#/pagar/\(accountId)")!
    }

    /// Guía institucional de medios de pago.
    static let comoPagar = URL(string: "https://www.metrogas.com.ar/hogares/paginas/como-pagar-tu-factura.aspx")!

    static let m360InvoiceList = URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicinvoice/listR2")!
    static let m360Billing = URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicbilling/r2")!
    static let m360PublicAccount = URL(string: "https://saldos.micuenta.metrogas.com.ar/OvServiceHub/api/v1/M360/publicAccount")!

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
            || h.contains("authn.br1.hana.ondemand.com")
            || h.contains("login.microsoftonline.com")
            || h.contains("accounts.google.com")
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
