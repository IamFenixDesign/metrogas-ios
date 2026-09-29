import Foundation

enum MetrogasURLs {
    /// Landing de Oficina Virtual (registro / acceso).
    static let oficinaVirtual = URL(string: "https://registro.micuenta.metrogas.com.ar/")!

    /// Portal móvil oficial (misma entrada que usa la web de MetroGAS en mobile).
    static let portalMobile = URL(string: "https://portal.micuenta.metrogas.com.ar/sites/ovmetrogasmobile")!

    /// Portal escritorio.
    static let portalDesktop = URL(string: "https://portal.micuenta.metrogas.com.ar/")!

    /// Registro de usuario en Oficina Virtual.
    static let registro = URL(string: "https://registro.micuenta.metrogas.com.ar/indexUserReg.html")!

    static let ayudaRegistro = URL(string: "https://www.metrogas.com.ar/")!
    static let sitioInstitucional = URL(string: "https://www.metrogas.com.ar/")!

    static func isMetrogasAuthHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("accounts.ondemand.com")
            || h.contains("authn.br1.hana.ondemand.com")
            || h.contains("login.microsoftonline.com")
    }

    static func isMetrogasPortalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("portal.micuenta.metrogas.com.ar")
            || h.contains("dispatcher.br1.hana.ondemand.com")
            || h.contains("micuenta.metrogas.com.ar")
    }
}
