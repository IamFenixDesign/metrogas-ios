# Metrogas (iOS)

App nativa SwiftUI de demostración para gestionar/consultar facturas y consumo de gas natural, con datos mock estilo Metrogas (Argentina). Funciona offline, sin autenticación a APIs reales.

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

Si Xcode pide un Development Team para firmar, en el target **Metrogas → Signing & Capabilities** elegí tu equipo personal (Apple ID). Para simulador suele alcanzar con Automatic signing.

## Qué incluye

| Pantalla | Contenido |
|---|---|
| **Inicio** | Marca Metrogas, próxima factura, métricas rápidas, actividad reciente |
| **Facturas** | Listado con búsqueda y filtros (Todas / Pendientes / Pagadas / Vencidas) |
| **Detalle** | Monto ARS, período, vencimiento, estado, desglose, notas, marcar como pagada |
| **Consumo** | Selector 6/12 meses o año actual, gráfico de barras, comparación entre períodos, historial |
| **Cuenta** | Perfil demo, suministro, apariencia (sistema/claro/oscuro), restablecer datos |

Textos, fechas (`es_AR`) y moneda en **ARS**.

## Estructura

```
Metrogas/
├── Metrogas.xcodeproj
├── README.md
└── Metrogas/
    ├── MetrogasApp.swift
    ├── Models/
    ├── Data/          # MockDataStore + formatters
    ├── Theme/
    ├── Components/
    ├── Views/         # Home, Invoices, Consumption, Account
    └── Resources/Assets.xcassets
```

## Notas

- Los datos son de demostración y se pueden resetear desde **Cuenta**.
- Bundle ID: `ar.com.metrogas.demo`
- No hay integración con la API real de Metrogas.
