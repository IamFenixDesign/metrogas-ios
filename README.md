# MetroGAS (iOS)

App nativa SwiftUI para tu cuenta real de MetroGAS Argentina (Oficina Virtual).

Inicio, facturas, consumo y cuenta se muestran **dentro de la app** (SwiftUI). No se embebe el portal web.

## Requisitos

- macOS con **Xcode 15+** (o el IPA de GitHub Actions)
- iOS 17+
- Cuenta de Oficina Virtual MetroGAS ([registrarse](https://registro.micuenta.metrogas.com.ar/))

## Abrir y ejecutar

```bash
open Metrogas.xcodeproj
```

1. Ingresá con **email/contraseña** o **Continuar con Google** (abre solo el login de Google).
2. La app sincroniza facturas/consumo/cuenta con la sesión de Oficina Virtual.
3. Usá las pestañas nativas: Inicio, Facturas, Consumo, Cuenta.

## IPA

- Workflow: `.github/workflows/ios-ipa.yml`
- Descarga: https://github.com/IamFenixDesign/metrogas-ios/releases/download/metrogas-demo-ipa/Metrogas.ipa

El IPA por defecto es **unsigned**. Firma: `ci/SIGNING_SECRETS.md`.

## Cómo funciona

MetroGAS no publica una API abierta. Esta app:

1. Autentica de forma nativa contra SAP Identity (email/contraseña) o Google OAuth.
2. Sincroniza contra **OvServiceHub (M360)** y, si hace falta, captura las respuestas reales del portal UI5 (bridge oculto) para llenar pantallas SwiftUI.
3. Cachea el último sync en el dispositivo.
4. Al cerrar sesión, borra cookies y caché local.

WebViews: sheet de **Continuar con Google** (OAuth) y un bridge oculto solo para sync de datos (la UI sigue nativa).

## Estructura

```
Metrogas/
├── Data/        # Auth, sync, AccountDataStore
├── Views/Login  # Login nativo + Google
├── Views/Home|Invoices|Consumption|Account
└── Resources/   # Logo + brand
```
