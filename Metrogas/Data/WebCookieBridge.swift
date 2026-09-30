import Foundation
import WebKit

@MainActor
enum WebCookieBridge {
    static func syncHTTPCookiesToWebKit(_ cookies: [HTTPCookie]) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    static func syncWebKitCookiesToHTTP() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let jar = HTTPCookieStorage.shared
        for cookie in cookies {
            jar.setCookie(cookie)
        }
    }

    static func clearWebKitData() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    /// Borra datos de sitios MetroGAS/SAP y deja Google para “Continuar como…”.
    static func clearNonGoogleWebKitData() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let removable = records.filter { record in
            let name = record.displayName.lowercased()
            return !name.contains("google")
        }
        guard !removable.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataStore.removeData(ofTypes: types, for: removable) {
                continuation.resume()
            }
        }
    }
}
