import Foundation

enum MetrogasURLs {
    /// Landing de Oficina Virtual (registro / acceso).
    static let oficinaVirtual = URL(string: "https://registro.micuenta.metrogas.com.ar/")!

    /// Portal móvil oficial.
    static let portalMobile = URL(string: "https://portal.micuenta.metrogas.com.ar/sites/ovmetrogasmobile")!

    /// Portal principal OV2 (apps de facturas/consumo).
    static let portalOV2 = URL(string: "https://portal.micuenta.metrogas.com.ar/sites/ovmetrogas2")!

    /// Host de acceso (proxy autenticado al Service Hub).
    static let acceso = URL(string: "https://acceso.micuenta.metrogas.com.ar/")!

    static let accesoOV2 = URL(string: "https://acceso.micuenta.metrogas.com.ar/sites/ovmetrogas2")!

    /// Portal escritorio.
    static let portalDesktop = URL(string: "https://portal.micuenta.metrogas.com.ar/")!

    /// Registro de usuario en Oficina Virtual.
    static let registro = URL(string: "https://registro.micuenta.metrogas.com.ar/indexUserReg.html")!

    static let ayudaRegistro = URL(string: "https://www.metrogas.com.ar/")!
    static let sitioInstitucional = URL(string: "https://www.metrogas.com.ar/")!

    /// Endpoints conocidos / probables del OvServiceHub (M360).
    static let serviceHubCandidates: [URL] = [
        // Facturación / saldo
        "/OvServiceHub/api/v1/web/M360/invoices",
        "/OvServiceHub/api/v1/web/M360/invoice",
        "/OvServiceHub/api/v1/web/M360/facturas",
        "/OvServiceHub/api/v1/web/M360/factura",
        "/OvServiceHub/api/v1/web/M360/billing",
        "/OvServiceHub/api/v1/web/M360/bills",
        "/OvServiceHub/api/v1/web/M360/bill",
        "/OvServiceHub/api/v1/web/M360/balance",
        "/OvServiceHub/api/v1/web/M360/saldo",
        "/OvServiceHub/api/v1/web/M360/accountBalance",
        "/OvServiceHub/api/v1/web/M360/openItems",
        "/OvServiceHub/api/v1/web/M360/openItem",
        "/OvServiceHub/api/v1/web/M360/debt",
        "/OvServiceHub/api/v1/web/M360/deuda",
        // Consumo
        "/OvServiceHub/api/v1/web/M360/consumption",
        "/OvServiceHub/api/v1/web/M360/consumo",
        "/OvServiceHub/api/v1/web/M360/readings",
        "/OvServiceHub/api/v1/web/M360/lectura",
        "/OvServiceHub/api/v1/web/M360/usages",
        // Cuenta / BP
        "/OvServiceHub/api/v1/web/M360/account",
        "/OvServiceHub/api/v1/web/M360/cuenta",
        "/OvServiceHub/api/v1/web/M360/customer",
        "/OvServiceHub/api/v1/web/M360/businessPartner",
        "/OvServiceHub/api/v1/web/M360/bp",
        "/OvServiceHub/api/v1/web/M360/profile",
        "/OvServiceHub/api/v1/web/M360/home",
        "/OvServiceHub/api/v1/web/M360/dashboard",
        "/OvServiceHub/api/v1/secured/M360/invoices",
        "/OvServiceHub/api/v1/secured/M360/account",
        "/OvServiceHub/api/v1/secured/M360/consumption",
        "/OvServiceHub/api/v1/secured/M360/balance"
    ].flatMap { path -> [URL] in
        let hosts = [
            "https://acceso.micuenta.metrogas.com.ar",
            "https://portal.micuenta.metrogas.com.ar",
            "https://registro.micuenta.metrogas.com.ar"
        ]
        return hosts.compactMap { URL(string: $0 + path) }
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
            || h.contains("dispatcher.br1.hana.ondemand.com")
            || h.contains("micuenta.metrogas.com.ar")
    }
}
