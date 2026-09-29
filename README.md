# MetroGAS (iOS)

App nativa SwiftUI de demostración para gestionar/consultar facturas y consumo de gas natural, con datos mock estilo **MetroGAS Argentina**. Funciona offline, sin autenticación a APIs reales.

## Requisitos (desarrollo local)

- macOS con **Xcode 15+** (recomendado Xcode 16)
- Simulador iPhone o dispositivo físico con **iOS 17+**

## Abrir y ejecutar (Mac + Xcode)

1. Cloná o abrí esta carpeta en tu Mac.
2. Abrí el proyecto:
   ```bash
   open Metrogas.xcodeproj
   ```
3. Seleccioná el target **Metrogas** y un simulador → **Run** (⌘R).
4. La app pide permiso de **notificaciones locales** para recordatorios (también en **Cuenta**).

## Build IPA con GitHub Actions (sin Mac)

Workflow: [`.github/workflows/ios-ipa.yml`](.github/workflows/ios-ipa.yml)

### Qué hace

1. Corre en `macos-14` con Xcode.
2. Si **no** hay secrets de firma Apple → genera un **IPA unsigned** (artefacto descargable; no se instala en iPhone hasta resignarlo).
3. Si hay secrets de firma → archive + export firmado (`ad-hoc` por defecto).
4. Sube el archivo como artifact **`Metrogas-ipa`**.

### Cómo disparar

```bash
# Tras pushear este repo a GitHub:
gh workflow run ios-ipa.yml
# o: push a main / cursor/**
```

En GitHub: **Actions → Build Metrogas IPA → Run workflow**.

### Cómo descargar el IPA

1. Abrí el run en **Actions**.
2. Al final del job, sección **Artifacts** → **Metrogas-ipa**.
3. Descargá el zip y extraé `Metrogas.ipa`.

CLI:

```bash
gh run list --workflow=ios-ipa.yml
gh run download <RUN_ID> -n Metrogas-ipa
```

### Secrets para IPA instalable en dispositivo / App Store

Ver detalle en [`ci/SIGNING_SECRETS.md`](ci/SIGNING_SECRETS.md).

| Secret | Uso |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Certificado `.p12` en base64 |
| `APPLE_CERTIFICATE_PASSWORD` | Password del `.p12` |
| `APPLE_PROVISION_PROFILE_BASE64` | Perfil `.mobileprovision` en base64 (bundle `ar.com.metrogas.demo`) |
| `APPLE_TEAM_ID` | Team ID (10 caracteres) |
| `IOS_EXPORT_METHOD` | Opcional: `ad-hoc`, `development`, `app-store-connect`, `enterprise` |

Sin estos secrets el workflow **igual produce** un IPA artifact (unsigned).

### Firma / instalabilidad (honesto)

- **Unsigned IPA (default CI):** útil como build artifact; **no** se instala en un iPhone real sin resignar.
- **Signed ad-hoc / development:** instalable en devices registrados en el perfil.
- **App Store:** requiere `IOS_EXPORT_METHOD=app-store-connect` + distribución App Store.

## Publicar este proyecto en GitHub

Si el remoto aún no existe:

```bash
gh auth login
gh repo create metrogas-ios --public --source=. --remote=origin --push
gh workflow run ios-ipa.yml
```

## Qué incluye la app

| Pantalla | Contenido |
|---|---|
| **Inicio** | Logo oficial MetroGAS, próxima factura, próximos vencimientos, métricas |
| **Facturas** | Búsqueda y filtros |
| **Detalle** | ARS, período, vencimiento, desglose, notas, marcar pagada |
| **Consumo** | Gráficos e historial |
| **Cuenta** | Perfil demo, recordatorios, apariencia |

## Marca

- Logo: `https://www.metrogas.com.ar/assets/media/2022/08/metrogas-logo.svg`
- Colores: `#004cac`, `#00a6dd`, `#ff5200`
- Proveniencia: `Metrogas/Resources/Brand/SOURCE.txt`

## Notas

- Datos de demostración; Bundle ID: `ar.com.metrogas.demo`
- Sin API real de MetroGAS ni Apple Pay
