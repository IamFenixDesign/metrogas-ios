# MetroGAS (iOS)

App nativa SwiftUI de demostración para gestionar/consultar facturas y consumo de gas natural, con datos mock estilo **MetroGAS Argentina**. Funciona offline, sin autenticación a APIs reales.

## Requisitos

- macOS con **Xcode 15+** (recomendado Xcode 16)
- Simulador iPhone o dispositivo físico con **iOS 17+**

## Abrir y ejecutar

1. Cloná o abrí esta carpeta en tu Mac.
2. Abrí el proyecto:
   ```bash
   open Metrogas.xcodeproj
   ```
   O desde Xcode: **File → Open…** y elegí `Metrogas.xcodeproj`.
3. En la barra de esquema, seleccioná el target **Metrogas** y un simulador (por ejemplo **iPhone 16**).
4. Pulsá **Run** (⌘R).
5. Al iniciar, la app pide permiso de **notificaciones locales** para recordatorios de vencimiento (también configurable en **Cuenta**).

Si Xcode pide un Development Team para firmar, en el target **Metrogas → Signing & Capabilities** elegí tu equipo personal (Apple ID). Para simulador suele alcanzar con Automatic signing.

## Qué incluye

| Pantalla | Contenido |
|---|---|
| **Inicio** | Logo oficial MetroGAS, próxima factura, próximos vencimientos, métricas, actividad |
| **Facturas** | Listado con búsqueda y filtros (Todas / Pendientes / Pagadas / Vencidas) |
| **Detalle** | Monto ARS, período, vencimiento, estado, desglose, notas, marcar como pagada |
| **Consumo** | Selector 6/12 meses o año actual, gráfico de barras, comparación, historial |
| **Cuenta** | Perfil demo, recordatorios locales, apariencia, restablecer datos |

Textos, fechas (`es_AR`) y moneda en **ARS**.

## Marca y assets

- Logo oficial descargado de `https://www.metrogas.com.ar/assets/media/2022/08/metrogas-logo.svg`
- Colores del SVG: `#004cac`, `#00a6dd`, `#ff5200`, `#1a1818`
- Asset catalog: `MetrogasLogo` (claro/oscuro), `AppIcon`, `BrandBlue` / `BrandCyan` / `BrandFlame`
- Proveniencia: `Metrogas/Resources/Brand/SOURCE.txt`

## Recordatorios

- Notificaciones locales el día del vencimiento y N días antes (1–7, por defecto 3)
- Toggle y preferencias en **Cuenta → Recordatorios**
- Superficie in-app **Próximos vencimientos** en Inicio
- Las facturas pendientes/vencidas de demo usan fechas relativas a “hoy”

## Estructura

```
Metrogas/
├── Metrogas.xcodeproj
├── README.md
└── Metrogas/
    ├── MetrogasApp.swift
    ├── Models/
    ├── Data/          # MockDataStore, formatters, ReminderService
    ├── Theme/
    ├── Components/
    ├── Views/         # Home, Invoices, Consumption, Account, splash
    └── Resources/
        ├── Assets.xcassets
        └── Brand/     # SVG oficial + SOURCE.txt
```

## Notas

- Los datos son de demostración y se pueden resetear desde **Cuenta**.
- Bundle ID: `ar.com.metrogas.demo`
- No hay integración con la API real de MetroGAS ni Apple Pay.
