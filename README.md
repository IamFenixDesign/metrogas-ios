# MetroGAS (iOS)

App nativa SwiftUI para acceder a tu **cuenta real** de MetroGAS Argentina mediante la **Oficina Virtual oficial** (`micuenta.metrogas.com.ar`).

No incluye datos de demostración. Facturas y consumo se consultan en el portal oficial tras iniciar sesión.

## Requisitos

- macOS con **Xcode 15+** (o el IPA generado por GitHub Actions)
- iOS 17+
- Cuenta de Oficina Virtual MetroGAS ([registrarse](https://registro.micuenta.metrogas.com.ar/))

## Abrir y ejecutar

```bash
open Metrogas.xcodeproj
```

Target **Metrogas** → simulador o dispositivo → ⌘R.

1. En la pantalla de acceso ingresá **email y contraseña** de MetroGAS, o tocá **Continuar con Google**.
2. Con Google se abre el login oficial de `accounts.google.com` (no la web completa de MetroGAS).
3. Tras autenticarte, usá las pestañas Facturas / Consumo / Cuenta para el portal oficial.

## IPA (GitHub Actions)

- Workflow: `.github/workflows/ios-ipa.yml`
- Release: https://github.com/IamFenixDesign/metrogas-ios/releases/tag/metrogas-demo-ipa
- Descarga directa: https://github.com/IamFenixDesign/metrogas-ios/releases/download/metrogas-demo-ipa/Metrogas.ipa

El IPA por defecto es **unsigned** (no instalable en iPhone real sin resignar). Secrets de firma: `ci/SIGNING_SECRETS.md`.

## Diseño y marca

- Logo oficial MetroGAS y colores `#004cac` / `#00a6dd` / `#ff5200`
- Login nativo brand-forward, splash y shell alrededor del portal

## Privacidad / cómo funciona el login

MetroGAS no publica una API abierta para terceros. Esta app:

1. Hace el **login nativo** contra SAP Identity de MetroGAS (email/contraseña por HTTP).
2. Para Google, obtiene la URL OAuth oficial y abre **solo** el login de Google.
3. Comparte la sesión (cookies) con el `WKWebView` del portal.
4. Al **cerrar sesión**, borra cookies y datos web del dispositivo.

No se inventan facturas ni se usan perfiles ficticios.

## Estructura

```
Metrogas/
├── Data/        # AppSession, MetrogasAuthService, cookies, URLs
├── Views/Login  # Login nativo + GoogleAuth
├── Views/Portal # WKWebView Oficina Virtual
├── Views/Home|Invoices|Consumption|Account
└── Resources/   # Logo + brand assets
```
