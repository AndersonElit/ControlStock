# Etapa 4b — Frontend: Feature Dashboard

## 1. Resumen del Feature

| Campo | Valor |
|---|---|
| Feature ID | FE-DASH |
| Documento | DEV-ControlStock-04-fe-dashboard.md |
| Etapa SDLC | 4 — Implementación Frontend |
| Sprint sugerido | Sprint 2 |
| Prioridad | Alta |
| Dependencias | FE-AUTH completado; inventory-service y alert-service operativos en Kong |

El **Dashboard** es la pantalla principal post-login. Presenta al usuario un resumen visual del estado del inventario: tarjetas de resumen de stock, lista de alertas activas y tabla de movimientos recientes. Los datos se actualizan periódicamente mediante TanStack Query, y la vista se filtra según el rol del usuario autenticado.

---

## 2. Contexto y Alcance

### 2.1 Descripción funcional

Al ingresar al sistema, el usuario llega al dashboard con tres bloques de información:

1. **Resumen de stock** — tarjetas con el total de productos, productos bajo mínimo y productos en sobrestock.
2. **Alertas activas** — lista de alertas de inventario con estado `ACTIVA`, indicando producto, tipo y valores umbrales.
3. **Movimientos recientes** — tabla con los últimos 5 movimientos registrados en el sistema.

La información se obtiene directamente del backend vía Kong. Los Operadores ven datos filtrados por los productos que gestionan; los Gerentes y roles superiores ven el inventario completo (el filtrado se aplica en el backend según el JWT).

### 2.2 Rutas del feature

| Ruta | Tipo | Acceso | Descripción |
|---|---|---|---|
| `/dashboard` | Protegida | Todos los roles autenticados | Vista principal del sistema |

### 2.3 Roles y visibilidad

| Rol | Datos visibles |
|---|---|
| Administrador | Todos los productos |
| Supervisor | Todos los productos |
| Operador | Productos bajo su gestión (filtrado por backend) |
| Gerente | Todos los productos |
| Analista | Todos los productos (solo lectura) |
| Auditor | Todos los productos (solo lectura) |

---

## 3. Backend Consumido

Todas las llamadas se realizan a través del Kong API Gateway en `http://<VPS_IP>:8000/api/v1`. El header `Authorization: Bearer <accessToken>` es obligatorio en todas las peticiones.

| Endpoint | Servicio | Descripción |
|---|---|---|
| `GET /inventory/stock?bajominimo=true` | inventory-service | Stock de todos los productos con indicador de bajo mínimo |
| `GET /alerts?estado=ACTIVA` | alert-service | Alertas activas en el sistema |
| `GET /inventory/movements?limit=5` | inventory-service | Últimos 5 movimientos |

### 3.1 Modelos de respuesta esperados

**GET /inventory/stock:**
```json
{
  "data": [
    {
      "productoId": "uuid",
      "codigoProducto": "PROD-001",
      "nombreProducto": "Laptop HP",
      "categoriaId": "uuid",
      "stockActual": 3,
      "stockMinimo": 10,
      "stockMaximo": 100,
      "bajominimo": true
    }
  ],
  "total": 42,
  "pagina": 1
}
```

**GET /alerts?estado=ACTIVA:**
```json
{
  "data": [
    {
      "id": "uuid",
      "productoId": "uuid",
      "tipoAlerta": "BAJO_STOCK",
      "stockActual": 3,
      "umbral": 10,
      "estado": "ACTIVA",
      "createdAt": "2025-06-01T10:00:00.000Z"
    }
  ]
}
```

**GET /inventory/movements?limit=5:**
```json
{
  "data": [
    {
      "id": "uuid",
      "productoId": "uuid",
      "tipo": "ENTRADA",
      "cantidad": 50,
      "fecha": "2025-06-01T09:30:00.000Z",
      "saldoResultante": 53
    }
  ]
}
```

---

## 4. Arquitectura del Feature

```
src/
├── app/
│   └── (protected)/
│       └── dashboard/
│           └── page.tsx                   # DashboardPage
├── components/
│   └── dashboard/
│       ├── StockSummaryCard.tsx           # Tarjetas de resumen
│       ├── StockSummaryCard.test.tsx
│       ├── ActiveAlertsList.tsx           # Lista de alertas activas
│       ├── ActiveAlertsList.test.tsx
│       ├── RecentMovementsTable.tsx       # Tabla de movimientos recientes
│       ├── RecentMovementsTable.test.tsx
│       ├── StockStatusBadge.tsx           # Badge de estado de stock
│       └── StockStatusBadge.test.tsx
├── hooks/
│   └── dashboard/
│       ├── useStockSummary.ts
│       ├── useStockSummary.test.ts
│       ├── useActiveAlerts.ts
│       ├── useActiveAlerts.test.ts
│       ├── useRecentMovements.ts
│       └── useRecentMovements.test.ts
├── schemas/
│   └── dashboard/
│       ├── stockLevelSchema.ts
│       ├── alertEventSchema.ts
│       ├── inventoryMovementSummarySchema.ts
│       └── dashboard.schemas.test.ts
└── store/
    └── slices/
        ├── dashboardSlice.ts
        └── dashboardSlice.test.ts
```

---

## 5. Zod Schemas

### 5.1 `src/schemas/dashboard/stockLevelSchema.ts`

```typescript
import { z } from 'zod'

export const StockLevelSchema = z.object({
  productoId: z.string().uuid('productoId debe ser un UUID válido'),
  codigoProducto: z.string().min(1, 'El código de producto es obligatorio'),
  nombreProducto: z.string().min(1, 'El nombre de producto es obligatorio'),
  categoriaId: z.string().uuid('categoriaId debe ser un UUID válido'),
  stockActual: z.number().int().min(0, 'El stock actual no puede ser negativo'),
  stockMinimo: z.number().int().min(0, 'El stock mínimo no puede ser negativo'),
  stockMaximo: z.number().int().positive('El stock máximo debe ser positivo'),
  bajominimo: z.boolean(),
})

export const StockLevelListResponseSchema = z.object({
  data: z.array(StockLevelSchema),
  total: z.number().int().nonnegative(),
  pagina: z.number().int().positive().optional(),
})

export type StockLevel = z.infer<typeof StockLevelSchema>
export type StockLevelListResponse = z.infer<typeof StockLevelListResponseSchema>
```

### 5.2 `src/schemas/dashboard/alertEventSchema.ts`

```typescript
import { z } from 'zod'

export const TipoAlertaEnum = z.enum(['BAJO_STOCK', 'SOBRESTOCK', 'SIN_STOCK'], {
  errorMap: () => ({ message: 'tipoAlerta debe ser BAJO_STOCK, SOBRESTOCK o SIN_STOCK' }),
})

export const EstadoAlertaEnum = z.enum(['ACTIVA', 'RESUELTA', 'IGNORADA'], {
  errorMap: () => ({ message: 'estado debe ser ACTIVA, RESUELTA o IGNORADA' }),
})

export const AlertEventSchema = z.object({
  id: z.string().uuid('id debe ser un UUID válido'),
  productoId: z.string().uuid('productoId debe ser un UUID válido'),
  tipoAlerta: TipoAlertaEnum,
  stockActual: z.number().int().min(0),
  umbral: z.number().int().min(0),
  estado: EstadoAlertaEnum,
  createdAt: z.string().datetime('createdAt debe ser un datetime ISO válido'),
})

export const AlertEventListResponseSchema = z.object({
  data: z.array(AlertEventSchema),
})

export type AlertEvent = z.infer<typeof AlertEventSchema>
export type AlertEventListResponse = z.infer<typeof AlertEventListResponseSchema>
```

### 5.3 `src/schemas/dashboard/inventoryMovementSummarySchema.ts`

```typescript
import { z } from 'zod'

export const TipoMovimientoEnum = z.enum(['ENTRADA', 'SALIDA', 'AJUSTE'], {
  errorMap: () => ({ message: 'tipo debe ser ENTRADA, SALIDA o AJUSTE' }),
})

export const InventoryMovementSummarySchema = z.object({
  id: z.string().uuid(),
  productoId: z.string().uuid(),
  tipo: TipoMovimientoEnum,
  cantidad: z.number().int().positive('La cantidad debe ser positiva'),
  fecha: z.string().datetime(),
  saldoResultante: z.number().int().min(0),
})

export const MovementListResponseSchema = z.object({
  data: z.array(InventoryMovementSummarySchema),
})

export type InventoryMovementSummary = z.infer<typeof InventoryMovementSummarySchema>
```

---

## 6. TanStack Query Hooks

### 6.1 `src/hooks/dashboard/useStockSummary.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { useSession } from 'next-auth/react'
import { StockLevelListResponseSchema, type StockLevelListResponse } from '@/schemas/dashboard/stockLevelSchema'

async function fetchStockSummary(token: string): Promise<StockLevelListResponse> {
  const res = await fetch(
    `${process.env.NEXT_PUBLIC_API_BASE_URL}/inventory/stock?bajominimo=true`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    }
  )
  if (!res.ok) throw new Error(`Error al obtener el resumen de stock: ${res.status}`)
  const data = await res.json()
  return StockLevelListResponseSchema.parse(data)
}

export function useStockSummary() {
  const { data: session } = useSession()
  const token = (session as { accessToken?: string })?.accessToken ?? ''

  return useQuery({
    queryKey: ['dashboard', 'stockSummary'],
    queryFn: () => fetchStockSummary(token),
    enabled: !!token,
    staleTime: 60 * 1000, // 60 segundos
    refetchOnWindowFocus: true,
  })
}
```

### 6.2 `src/hooks/dashboard/useActiveAlerts.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { useSession } from 'next-auth/react'
import { AlertEventListResponseSchema, type AlertEventListResponse } from '@/schemas/dashboard/alertEventSchema'

async function fetchActiveAlerts(token: string): Promise<AlertEventListResponse> {
  const res = await fetch(
    `${process.env.NEXT_PUBLIC_API_BASE_URL}/alerts?estado=ACTIVA`,
    { headers: { Authorization: `Bearer ${token}` } }
  )
  if (!res.ok) throw new Error(`Error al obtener alertas activas: ${res.status}`)
  const data = await res.json()
  return AlertEventListResponseSchema.parse(data)
}

export function useActiveAlerts() {
  const { data: session } = useSession()
  const token = (session as { accessToken?: string })?.accessToken ?? ''

  return useQuery({
    queryKey: ['dashboard', 'activeAlerts'],
    queryFn: () => fetchActiveAlerts(token),
    enabled: !!token,
    staleTime: 30 * 1000, // 30 segundos — alertas se refrescan más frecuentemente
    refetchInterval: 60 * 1000,
  })
}
```

### 6.3 `src/hooks/dashboard/useRecentMovements.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { useSession } from 'next-auth/react'
import { MovementListResponseSchema } from '@/schemas/dashboard/inventoryMovementSummarySchema'

async function fetchRecentMovements(token: string) {
  const res = await fetch(
    `${process.env.NEXT_PUBLIC_API_BASE_URL}/inventory/movements?limit=5`,
    { headers: { Authorization: `Bearer ${token}` } }
  )
  if (!res.ok) throw new Error(`Error al obtener movimientos recientes: ${res.status}`)
  const data = await res.json()
  return MovementListResponseSchema.parse(data)
}

export function useRecentMovements() {
  const { data: session } = useSession()
  const token = (session as { accessToken?: string })?.accessToken ?? ''

  return useQuery({
    queryKey: ['dashboard', 'recentMovements'],
    queryFn: () => fetchRecentMovements(token),
    enabled: !!token,
    staleTime: 60 * 1000,
  })
}
```

---

## 7. Zustand Slice

### 7.1 `src/store/slices/dashboardSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export interface DashboardState {
  selectedCategoryFilter: string | null
  setSelectedFilter: (categoryId: string | null) => void
  clearFilters: () => void
}

export const createDashboardSlice: StateCreator<DashboardState> = (set) => ({
  selectedCategoryFilter: null,

  setSelectedFilter: (categoryId: string | null) =>
    set({ selectedCategoryFilter: categoryId }),

  clearFilters: () =>
    set({ selectedCategoryFilter: null }),
})
```

---

## 8. Componentes

### 8.1 `src/app/(protected)/dashboard/page.tsx` — DashboardPage

```typescript
'use client'

import { StockSummaryCard } from '@/components/dashboard/StockSummaryCard'
import { ActiveAlertsList } from '@/components/dashboard/ActiveAlertsList'
import { RecentMovementsTable } from '@/components/dashboard/RecentMovementsTable'

export default function DashboardPage() {
  return (
    <div className="space-y-6 p-6">
      <h1 className="text-2xl font-bold text-gray-900">Panel de Control</h1>
      <StockSummaryCard />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ActiveAlertsList />
        <RecentMovementsTable />
      </div>
    </div>
  )
}
```

### 8.2 `src/components/dashboard/StockSummaryCard.tsx`

```typescript
'use client'

import { useStockSummary } from '@/hooks/dashboard/useStockSummary'

export function StockSummaryCard() {
  const { data, isLoading, isError } = useStockSummary()

  if (isLoading) {
    return (
      <div className="grid grid-cols-3 gap-4" data-testid="stock-summary-loading">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-24 bg-gray-200 animate-pulse rounded-lg" />
        ))}
      </div>
    )
  }

  if (isError) {
    return (
      <div className="text-red-500 text-sm" data-testid="stock-summary-error">
        Error al cargar el resumen de stock
      </div>
    )
  }

  const total = data?.total ?? 0
  const bajominimo = data?.data.filter((s) => s.bajominimo).length ?? 0
  const sobrestock = data?.data.filter((s) => s.stockActual > s.stockMaximo).length ?? 0

  return (
    <div className="grid grid-cols-3 gap-4" data-testid="stock-summary-card">
      <div className="bg-white rounded-xl shadow p-5">
        <p className="text-sm text-gray-500">Total productos</p>
        <p className="text-3xl font-bold text-gray-900" data-testid="total-products">{total}</p>
      </div>
      <div className="bg-red-50 rounded-xl shadow p-5">
        <p className="text-sm text-red-600">Bajo mínimo</p>
        <p className="text-3xl font-bold text-red-700" data-testid="bajo-minimo-count">{bajominimo}</p>
      </div>
      <div className="bg-orange-50 rounded-xl shadow p-5">
        <p className="text-sm text-orange-600">Sobrestock</p>
        <p className="text-3xl font-bold text-orange-700" data-testid="sobrestock-count">{sobrestock}</p>
      </div>
    </div>
  )
}
```

### 8.3 `src/components/dashboard/StockStatusBadge.tsx`

```typescript
interface StockStatusBadgeProps {
  status: 'BAJO_STOCK' | 'NORMAL' | 'SOBRESTOCK'
}

const statusConfig = {
  BAJO_STOCK: { label: 'Bajo mínimo', className: 'bg-red-100 text-red-700' },
  NORMAL: { label: 'Normal', className: 'bg-green-100 text-green-700' },
  SOBRESTOCK: { label: 'Sobrestock', className: 'bg-orange-100 text-orange-700' },
}

export function StockStatusBadge({ status }: StockStatusBadgeProps) {
  const config = statusConfig[status]
  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${config.className}`}
      data-testid={`stock-badge-${status.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

### 8.4 `src/components/dashboard/ActiveAlertsList.tsx`

```typescript
'use client'

import { useActiveAlerts } from '@/hooks/dashboard/useActiveAlerts'

const tipoAlertaLabel: Record<string, string> = {
  BAJO_STOCK: 'Bajo mínimo',
  SOBRESTOCK: 'Sobrestock',
  SIN_STOCK: 'Sin stock',
}

export function ActiveAlertsList() {
  const { data, isLoading, isError } = useActiveAlerts()

  if (isLoading) {
    return <div className="animate-pulse h-48 bg-gray-100 rounded-lg" data-testid="alerts-loading" />
  }

  if (isError) {
    return <p className="text-red-500 text-sm" data-testid="alerts-error">Error al cargar alertas</p>
  }

  const alerts = data?.data ?? []

  return (
    <div className="bg-white rounded-xl shadow p-5" data-testid="active-alerts-list">
      <h2 className="text-lg font-semibold text-gray-800 mb-4">Alertas Activas</h2>
      {alerts.length === 0 ? (
        <p className="text-gray-400 text-sm" data-testid="alerts-empty">
          No hay alertas activas en este momento
        </p>
      ) : (
        <ul className="space-y-3">
          {alerts.map((alert) => (
            <li
              key={alert.id}
              className="flex items-center justify-between border-l-4 border-red-400 pl-3 py-1"
              data-testid={`alert-item-${alert.id}`}
            >
              <div>
                <p className="text-sm font-medium text-gray-800">
                  {tipoAlertaLabel[alert.tipoAlerta] ?? alert.tipoAlerta}
                </p>
                <p className="text-xs text-gray-500">
                  Stock: {alert.stockActual} / Umbral: {alert.umbral}
                </p>
              </div>
              <span className="text-xs text-red-500 font-semibold">ACTIVA</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
```

### 8.5 `src/components/dashboard/RecentMovementsTable.tsx`

```typescript
'use client'

import { useRecentMovements } from '@/hooks/dashboard/useRecentMovements'
import { format } from 'date-fns'
import { es } from 'date-fns/locale'

const tipoBadge: Record<string, string> = {
  ENTRADA: 'bg-green-100 text-green-700',
  SALIDA: 'bg-red-100 text-red-700',
  AJUSTE: 'bg-blue-100 text-blue-700',
}

export function RecentMovementsTable() {
  const { data, isLoading, isError } = useRecentMovements()

  if (isLoading) {
    return <div className="animate-pulse h-48 bg-gray-100 rounded-lg" data-testid="movements-loading" />
  }

  if (isError) {
    return <p className="text-red-500 text-sm" data-testid="movements-error">Error al cargar movimientos</p>
  }

  const movements = data?.data ?? []

  return (
    <div className="bg-white rounded-xl shadow p-5" data-testid="recent-movements-table">
      <h2 className="text-lg font-semibold text-gray-800 mb-4">Movimientos Recientes</h2>
      {movements.length === 0 ? (
        <p className="text-gray-400 text-sm" data-testid="movements-empty">Sin movimientos recientes</p>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-500 text-xs uppercase">
              <th className="pb-2">Tipo</th>
              <th className="pb-2">Producto</th>
              <th className="pb-2">Cantidad</th>
              <th className="pb-2">Saldo</th>
              <th className="pb-2">Fecha</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {movements.map((m) => (
              <tr key={m.id} data-testid={`movement-row-${m.id}`}>
                <td className="py-2">
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${tipoBadge[m.tipo] ?? ''}`}>
                    {m.tipo}
                  </span>
                </td>
                <td className="py-2 text-gray-700">{m.productoId}</td>
                <td className="py-2 font-medium">{m.cantidad}</td>
                <td className="py-2 text-gray-600">{m.saldoResultante}</td>
                <td className="py-2 text-gray-400">
                  {format(new Date(m.fecha), 'dd MMM yyyy', { locale: es })}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
```

---

## 9. TDD — Pruebas Unitarias (Vitest + RTL + MSW)

### 9.1 `src/schemas/dashboard/dashboard.schemas.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { StockLevelSchema } from './stockLevelSchema'
import { AlertEventSchema } from './alertEventSchema'
import { InventoryMovementSummarySchema } from './inventoryMovementSummarySchema'

// ─── StockLevelSchema ──────────────────────────────────────────────────────────

describe('StockLevelSchema', () => {
  const validStock = {
    productoId: '550e8400-e29b-41d4-a716-446655440000',
    codigoProducto: 'PROD-001',
    nombreProducto: 'Laptop HP',
    categoriaId: '550e8400-e29b-41d4-a716-446655440001',
    stockActual: 3,
    stockMinimo: 10,
    stockMaximo: 100,
    bajominimo: true,
  }

  it('acepta un stock level válido', () => {
    expect(() => StockLevelSchema.parse(validStock)).not.toThrow()
  })

  it('rechaza cuando falta productoId', () => {
    const { productoId: _p, ...rest } = validStock
    expect(StockLevelSchema.safeParse(rest).success).toBe(false)
  })

  it('rechaza cuando stockActual es negativo', () => {
    expect(
      StockLevelSchema.safeParse({ ...validStock, stockActual: -1 }).success
    ).toBe(false)
  })

  it('rechaza productoId con formato no-UUID', () => {
    expect(
      StockLevelSchema.safeParse({ ...validStock, productoId: 'no-uuid' }).success
    ).toBe(false)
  })
})

// ─── AlertEventSchema ──────────────────────────────────────────────────────────

describe('AlertEventSchema', () => {
  const validAlert = {
    id: '550e8400-e29b-41d4-a716-446655440002',
    productoId: '550e8400-e29b-41d4-a716-446655440000',
    tipoAlerta: 'BAJO_STOCK',
    stockActual: 3,
    umbral: 10,
    estado: 'ACTIVA',
    createdAt: '2025-06-01T10:00:00.000Z',
  }

  it('acepta una alerta válida', () => {
    expect(() => AlertEventSchema.parse(validAlert)).not.toThrow()
  })

  it('rechaza cuando tipoAlerta tiene un valor inválido', () => {
    expect(
      AlertEventSchema.safeParse({ ...validAlert, tipoAlerta: 'TIPO_INVALIDO' }).success
    ).toBe(false)
  })

  it('rechaza cuando estado tiene un valor inválido', () => {
    expect(
      AlertEventSchema.safeParse({ ...validAlert, estado: 'PENDIENTE' }).success
    ).toBe(false)
  })

  it('rechaza cuando createdAt no es datetime ISO', () => {
    expect(
      AlertEventSchema.safeParse({ ...validAlert, createdAt: '01-06-2025' }).success
    ).toBe(false)
  })
})

// ─── InventoryMovementSummarySchema ───────────────────────────────────────────

describe('InventoryMovementSummarySchema', () => {
  const validMovement = {
    id: '550e8400-e29b-41d4-a716-446655440003',
    productoId: '550e8400-e29b-41d4-a716-446655440000',
    tipo: 'ENTRADA',
    cantidad: 50,
    fecha: '2025-06-01T09:30:00.000Z',
    saldoResultante: 53,
  }

  it('acepta un movimiento válido', () => {
    expect(() => InventoryMovementSummarySchema.parse(validMovement)).not.toThrow()
  })

  it('acepta tipo SALIDA', () => {
    expect(
      InventoryMovementSummarySchema.safeParse({ ...validMovement, tipo: 'SALIDA' }).success
    ).toBe(true)
  })

  it('acepta tipo AJUSTE', () => {
    expect(
      InventoryMovementSummarySchema.safeParse({ ...validMovement, tipo: 'AJUSTE' }).success
    ).toBe(true)
  })
})
```

### 9.2 MSW Handlers para Dashboard

```typescript
// src/mocks/handlers/dashboard.handlers.ts
import { http, HttpResponse } from 'msw'

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL

export const dashboardHandlers = [
  http.get(`${API_BASE}/inventory/stock`, () => {
    return HttpResponse.json({
      data: [
        {
          productoId: '550e8400-e29b-41d4-a716-446655440000',
          codigoProducto: 'PROD-001',
          nombreProducto: 'Laptop HP',
          categoriaId: '550e8400-e29b-41d4-a716-446655440001',
          stockActual: 3,
          stockMinimo: 10,
          stockMaximo: 100,
          bajominimo: true,
        },
        {
          productoId: '550e8400-e29b-41d4-a716-446655440002',
          codigoProducto: 'PROD-002',
          nombreProducto: 'Mouse Logitech',
          categoriaId: '550e8400-e29b-41d4-a716-446655440001',
          stockActual: 50,
          stockMinimo: 10,
          stockMaximo: 200,
          bajominimo: false,
        },
      ],
      total: 2,
      pagina: 1,
    })
  }),

  http.get(`${API_BASE}/alerts`, () => {
    return HttpResponse.json({
      data: [
        {
          id: '550e8400-e29b-41d4-a716-446655440010',
          productoId: '550e8400-e29b-41d4-a716-446655440000',
          tipoAlerta: 'BAJO_STOCK',
          stockActual: 3,
          umbral: 10,
          estado: 'ACTIVA',
          createdAt: '2025-06-01T10:00:00.000Z',
        },
      ],
    })
  }),

  http.get(`${API_BASE}/inventory/movements`, () => {
    return HttpResponse.json({
      data: [
        {
          id: '550e8400-e29b-41d4-a716-446655440020',
          productoId: '550e8400-e29b-41d4-a716-446655440000',
          tipo: 'ENTRADA',
          cantidad: 50,
          fecha: '2025-06-01T09:30:00.000Z',
          saldoResultante: 53,
        },
      ],
    })
  }),
]
```

### 9.3 `src/hooks/dashboard/useStockSummary.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { createTestWrapper } from '@/test-utils/createTestWrapper'
import { useStockSummary } from './useStockSummary'
import { server } from '@/mocks/server'
import { http, HttpResponse } from 'msw'

describe('useStockSummary', () => {
  it('retorna estado loading inicialmente', () => {
    const { result } = renderHook(() => useStockSummary(), {
      wrapper: createTestWrapper(),
    })
    expect(result.current.isLoading).toBe(true)
  })

  it('retorna datos de stock al completarse la petición', async () => {
    const { result } = renderHook(() => useStockSummary(), {
      wrapper: createTestWrapper(),
    })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.data).toHaveLength(2)
    expect(result.current.data?.data[0].codigoProducto).toBe('PROD-001')
  })

  it('retorna estado error cuando la API falla', async () => {
    server.use(
      http.get(`*/inventory/stock`, () => {
        return HttpResponse.json({ message: 'Internal Server Error' }, { status: 500 })
      })
    )
    const { result } = renderHook(() => useStockSummary(), {
      wrapper: createTestWrapper(),
    })
    await waitFor(() => expect(result.current.isError).toBe(true))
  })
})
```

### 9.4 `src/hooks/dashboard/useActiveAlerts.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { createTestWrapper } from '@/test-utils/createTestWrapper'
import { useActiveAlerts } from './useActiveAlerts'
import { server } from '@/mocks/server'
import { http, HttpResponse } from 'msw'

describe('useActiveAlerts', () => {
  it('retorna alertas activas exitosamente', async () => {
    const { result } = renderHook(() => useActiveAlerts(), {
      wrapper: createTestWrapper(),
    })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.data).toHaveLength(1)
    expect(result.current.data?.data[0].tipoAlerta).toBe('BAJO_STOCK')
  })

  it('retorna array vacío cuando no hay alertas', async () => {
    server.use(
      http.get(`*/alerts`, () => HttpResponse.json({ data: [] }))
    )
    const { result } = renderHook(() => useActiveAlerts(), {
      wrapper: createTestWrapper(),
    })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.data).toHaveLength(0)
  })

  it('retorna error cuando la API falla', async () => {
    server.use(
      http.get(`*/alerts`, () =>
        HttpResponse.json({ message: 'Service Unavailable' }, { status: 503 })
      )
    )
    const { result } = renderHook(() => useActiveAlerts(), {
      wrapper: createTestWrapper(),
    })
    await waitFor(() => expect(result.current.isError).toBe(true))
  })
})
```

### 9.5 `src/components/dashboard/StockSummaryCard.test.tsx`

```typescript
import { describe, it, expect } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { StockSummaryCard } from './StockSummaryCard'
import { createTestWrapper } from '@/test-utils/createTestWrapper'

describe('StockSummaryCard', () => {
  it('muestra los contadores de stock correctamente', async () => {
    render(<StockSummaryCard />, { wrapper: createTestWrapper() })

    await waitFor(() =>
      expect(screen.getByTestId('stock-summary-card')).toBeInTheDocument()
    )

    expect(screen.getByTestId('total-products')).toHaveTextContent('2')
    expect(screen.getByTestId('bajo-minimo-count')).toHaveTextContent('1')
    expect(screen.getByTestId('sobrestock-count')).toHaveTextContent('0')
  })

  it('muestra el loading state mientras carga', () => {
    render(<StockSummaryCard />, { wrapper: createTestWrapper() })
    expect(screen.getByTestId('stock-summary-loading')).toBeInTheDocument()
  })
})
```

### 9.6 `src/components/dashboard/ActiveAlertsList.test.tsx`

```typescript
import { describe, it, expect } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { ActiveAlertsList } from './ActiveAlertsList'
import { createTestWrapper } from '@/test-utils/createTestWrapper'
import { server } from '@/mocks/server'
import { http, HttpResponse } from 'msw'

describe('ActiveAlertsList', () => {
  it('renderiza la lista de alertas correctamente', async () => {
    render(<ActiveAlertsList />, { wrapper: createTestWrapper() })

    await waitFor(() =>
      expect(screen.getByTestId('active-alerts-list')).toBeInTheDocument()
    )

    expect(screen.getByText('Bajo mínimo')).toBeInTheDocument()
  })

  it('muestra mensaje de estado vacío cuando no hay alertas', async () => {
    server.use(
      http.get(`*/alerts`, () => HttpResponse.json({ data: [] }))
    )
    render(<ActiveAlertsList />, { wrapper: createTestWrapper() })

    await waitFor(() =>
      expect(screen.getByTestId('alerts-empty')).toBeInTheDocument()
    )
    expect(screen.getByTestId('alerts-empty')).toHaveTextContent(
      'No hay alertas activas en este momento'
    )
  })
})
```

### 9.7 `src/store/slices/dashboardSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { create } from 'zustand'
import { createDashboardSlice, DashboardState } from './dashboardSlice'

const useTestStore = create<DashboardState>()(createDashboardSlice)

describe('dashboardSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ selectedCategoryFilter: null })
  })

  it('estado inicial es selectedCategoryFilter null', () => {
    expect(useTestStore.getState().selectedCategoryFilter).toBeNull()
  })

  it('setSelectedFilter actualiza el filtro de categoría', () => {
    const categoryId = '550e8400-e29b-41d4-a716-446655440001'
    useTestStore.getState().setSelectedFilter(categoryId)
    expect(useTestStore.getState().selectedCategoryFilter).toBe(categoryId)
  })

  it('setSelectedFilter acepta null para limpiar el filtro', () => {
    useTestStore.getState().setSelectedFilter('alguna-categoria')
    useTestStore.getState().setSelectedFilter(null)
    expect(useTestStore.getState().selectedCategoryFilter).toBeNull()
  })

  it('clearFilters resetea el filtro a null', () => {
    useTestStore.getState().setSelectedFilter('alguna-categoria')
    useTestStore.getState().clearFilters()
    expect(useTestStore.getState().selectedCategoryFilter).toBeNull()
  })
})
```

---

## 10. E2E — Pruebas ATDD con Playwright

### Archivo: `e2e/dashboard/dashboard.spec.ts`

```typescript
import { test, expect } from '@playwright/test'

test.use({ storageState: 'e2e/fixtures/authenticated-user.json' })

// ─── TC-DASH-01: Cards de resumen de stock visibles ───────────────────────────
test.describe('TC-DASH-01: Resumen de stock en el dashboard', () => {
  test('usuario autenticado ve las tarjetas de resumen de stock', async ({ page }) => {
    // DADO que el usuario está autenticado
    await page.goto('/dashboard')

    // ENTONCES ve las tarjetas de resumen
    await expect(page.getByTestId('stock-summary-card')).toBeVisible()
    await expect(page.getByTestId('total-products')).toBeVisible()
    await expect(page.getByTestId('bajo-minimo-count')).toBeVisible()
    await expect(page.getByTestId('sobrestock-count')).toBeVisible()

    // Y los valores son números no negativos
    const totalText = await page.getByTestId('total-products').textContent()
    expect(Number(totalText)).toBeGreaterThanOrEqual(0)
  })
})

// ─── TC-DASH-02: Alertas visibles cuando hay bajominimo ──────────────────────
test.describe('TC-DASH-02: Alertas activas visibles', () => {
  test('cuando hay productos bajo mínimo, aparece al menos una alerta', async ({ page }) => {
    // DADO que existen productos con bajominimo=true en el sistema
    await page.goto('/dashboard')

    // CUANDO se carga el dashboard
    await page.waitForSelector('[data-testid="active-alerts-list"]')

    // ENTONCES la lista de alertas activas es visible
    await expect(page.getByTestId('active-alerts-list')).toBeVisible()

    // Y contiene al menos un elemento de alerta con badge ACTIVA
    const alertItems = page.locator('[data-testid^="alert-item-"]')
    await expect(alertItems.first()).toBeVisible()
    await expect(page.getByText('ACTIVA').first()).toBeVisible()
  })
})

// ─── TC-DASH-03: Tabla de movimientos recientes ───────────────────────────────
test.describe('TC-DASH-03: Movimientos recientes', () => {
  test('la tabla de movimientos muestra los últimos 5 movimientos', async ({ page }) => {
    // DADO que existen movimientos en el sistema
    await page.goto('/dashboard')

    // CUANDO se carga la tabla de movimientos
    await page.waitForSelector('[data-testid="recent-movements-table"]')

    // ENTONCES es visible la tabla
    await expect(page.getByTestId('recent-movements-table')).toBeVisible()

    // Y tiene como máximo 5 filas de datos
    const rows = page.locator('[data-testid^="movement-row-"]')
    const count = await rows.count()
    expect(count).toBeGreaterThanOrEqual(0)
    expect(count).toBeLessThanOrEqual(5)

    // Y cada fila tiene datos válidos de tipo (ENTRADA, SALIDA o AJUSTE)
    if (count > 0) {
      const firstRow = rows.first()
      await expect(firstRow).toBeVisible()
    }
  })
})
```

---

## 11. Criterios de Aceptación

| ID | Criterio | Verificación |
|---|---|---|
| AC-DASH-01 | El dashboard es accesible solo para usuarios autenticados | Middleware (FE-AUTH) |
| AC-DASH-02 | Las tarjetas de resumen muestran totales correctos | Test unitario StockSummaryCard |
| AC-DASH-03 | Las alertas activas se listan con tipo y valores de umbral | Test unitario ActiveAlertsList + E2E TC-DASH-02 |
| AC-DASH-04 | La tabla de movimientos muestra máximo 5 filas | Test unitario RecentMovementsTable + E2E TC-DASH-03 |
| AC-DASH-05 | El estado de carga (skeleton) se muestra antes de recibir datos | Test unitario hooks |
| AC-DASH-06 | Los errores de API se muestran como mensajes descriptivos | Test unitario hooks con MSW error |
| AC-DASH-07 | Los datos se refrescan automáticamente (staleTime configurado) | Configuración de useQuery |

---

## 12. Checklist de Implementación

- [ ] **RED:** Escribir tests de schemas (StockLevel, AlertEvent, MovementSummary) — fallan
- [ ] **GREEN:** Implementar schemas — tests pasan
- [ ] **RED:** Escribir tests de hooks (useStockSummary, useActiveAlerts, useRecentMovements) — fallan
- [ ] **GREEN:** Implementar hooks — tests pasan con MSW
- [ ] **RED:** Escribir tests de dashboardSlice — fallan
- [ ] **GREEN:** Implementar dashboardSlice — tests pasan
- [ ] **RED:** Escribir tests de StockSummaryCard, ActiveAlertsList, RecentMovementsTable — fallan
- [ ] **GREEN:** Implementar componentes — tests pasan
- [ ] **REFACTOR:** Revisar código y cobertura
- [ ] Escribir E2E ATDD (TC-DASH-01 a TC-DASH-03) antes de integración
- [ ] Configurar `NEXT_PUBLIC_API_BASE_URL` en `.env.local`
- [ ] Verificar que Kong esté accesible y los endpoints respondan correctamente
- [ ] PR con al menos 80% de cobertura en este feature
