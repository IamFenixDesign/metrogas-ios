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

1. En la pantalla de acceso tocá **Iniciar sesión**.
2. Completá el login oficial de MetroGAS (SAP Identity / Oficina Virtual).
3. Cuando veas tu portal, confirmá con **Ya inicié sesión** si la app no lo detectó sola.
4. Usá las pestañas Facturas / Consumo para navegar el portal, o los accesos desde Inicio.

## IPA (GitHub Actions)

- Workflow: `.github/workflows/ios-ipa.yml`
- Release: https://github.com/IamFenixDesign/metrogas-ios/releases/tag/metrogas-demo-ipa
- Descarga directa: https://github.com/IamFenixDesign/metrogas-ios/releases/download/metrogas-demo-ipa/Metrogas.ipa

El IPA por defecto es **unsigned** (no instalable en iPhone real sin resignar). Secrets de firma: `ci/SIGNING_SECRETS.md`.

## Diseño y marca

- Logo oficial MetroGAS y colores `#004cac` / `#00a6dd` / `#ff5200`
- Login brand-forward, splash y shell nativo alrededor del portal

## Privacidad / cómo funciona el login

MetroGAS no publica una API abierta para terceros. Esta app:

1. Abre el **login y portal oficiales** en un `WKWebView` seguro.
2. Conserva la sesión en el almacén web del sistema (cookies del dominio MetroGAS/SAP).
3. Al **cerrar sesión**, borra esos datos web del dispositivo.

No se inventan facturas ni se usan perfiles ficticios.

## Estructura

```
Metrogas/
├── Data/        # AppSession, MetrogasURLs, reminders
├── Views/Login  # Acceso oficial
├── Views/Portal # WKWebView Oficina Virtual
├── Views/Home|Invoices|Consumption|Account
└── Resources/   # Logo + brand assets
```
