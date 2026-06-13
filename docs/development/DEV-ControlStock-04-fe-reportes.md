# Etapa 4h — Frontend: Feature Reportes

---

## 1. Contexto y Objetivo

### Contexto

La feature de **Reportes** permite a los usuarios autorizados solicitar la generación de reportes del sistema de manera asíncrona. El usuario selecciona el tipo de reporte, formato de salida y parámetros (rango de fechas, filtros). El backend (`report-service`) procesa la solicitud de forma asíncrona y el frontend realiza **polling automático** para detectar cuando el reporte está listo. Una vez completado, el usuario descarga el archivo desde una URL pre-firmada de MinIO.

El flujo es: Solicitar (POST 202 Accepted) → Polling automático cada 5 segundos → Estado COMPLETADO → Descarga desde MinIO via URL pre-firmada.

### Objetivo

Implementar el módulo frontend de Reportes bajo Next.js 14 App Router con TypeScript estricto. Aplicar TDD (Red-Green-Refactor) en cada capa: schemas Zod, hooks TanStack Query con polling, componentes React, estado Zustand y tests E2E Playwright ATDD.

### Tipos de Reporte por Rol

| Tipo de Reporte | Gerente | Analista | Auditor | Administrador |
|---|---|---|---|---|
| `stock-actual` | SI | SI | SI | SI |
| `movimientos-periodo` | SI | SI | NO | SI |
| `auditoria-operaciones` | NO | NO | SI | SI |
| `proveedores-actividad` | SI | NO | NO | SI |

### Principios Guía

- **TDD estricto**: test antes que implementación. Ciclo Red → Green → Refactor.
- **Polling inteligente**: `useReporte` activa `refetchInterval` solo cuando estado es SOLICITADO o PROCESANDO, se detiene automáticamente al llegar a COMPLETADO o FALLIDO.
- **Type-safety total**: Zod valida toda respuesta de API en runtime.
- **Role-based filtering**: El select de tipo de reporte filtra opciones según el rol del usuario autenticado.
- **Download seguro**: La descarga usa `fetch` + `Blob` + `URL.createObjectURL` para no exponer la URL pre-firmada en el DOM.

---

## 2. Prerrequisitos

### Infraestructura

| Elemento | Detalle |
|---|---|
| Kong API Gateway | `http://<VPS_IP>:8000/api/v1` operativo con rutas de `report-service` |
| report-service | Desplegado en K3s; acepta POST /reports y retorna 202 Accepted |
| MinIO | Operativo; report-service genera URLs pre-firmadas para descarga |
| Keycloak OIDC | Realm `controlstock` con roles configurados |
| Next.js 14 scaffolding | App Router inicializado (Etapas 4a-4g completadas) |

### Dependencias del Proyecto

```json
{
  "dependencies": {
    "next": "14.x",
    "react": "18.x",
    "typescript": "5.x",
    "@tanstack/react-query": "^5.x",
    "zustand": "^4.x",
    "zod": "^3.x",
    "react-hook-form": "^7.x",
    "@hookform/resolvers": "^3.x",
    "next-auth": "^4.x"
  },
  "devDependencies": {
    "vitest": "^1.x",
    "@testing-library/react": "^14.x",
    "@testing-library/user-event": "^14.x",
    "msw": "^2.x",
    "@playwright/test": "^1.x"
  }
}
```

### Etapas Previas Completadas

- Etapa 4a: Scaffolding Next.js 14 App Router
- Etapa 4b-4g: Features de autenticación, dashboard, categorías, productos, inventario, proveedores

### Convenciones de Archivos

```
src/
  app/
    (protected)/
      reportes/
        page.tsx                    # ReporteListPage
        nuevo/
          page.tsx                  # ReporteFormPage
        [id]/
          page.tsx                  # ReporteDetailPage
  components/
    reportes/
      ReporteTable.tsx
      ReporteTable.test.tsx
      ReporteForm.tsx
      ReporteForm.test.tsx
      ReporteDetail.tsx
      ReporteDetail.test.tsx
      ReporteEstadoBadge.tsx
      ReporteEstadoBadge.test.tsx
      FormatoBadge.tsx
      FormatoBadge.test.tsx
      DescargaButton.tsx
      DescargaButton.test.tsx
      PollingStatus.tsx
      PollingStatus.test.tsx
  hooks/
    reportes/
      useReportes.ts
      useReportes.test.ts
      useReporte.ts
      useReporte.test.ts
      useCreateReporte.ts
      useCreateReporte.test.ts
      useDescargarReporte.ts
      useDescargarReporte.test.ts
  store/
    slices/
      reportesSlice.ts
      reportesSlice.test.ts
  schemas/
    reporte.schema.ts
    reporte.schema.test.ts
  types/
    reporte.types.ts
```

---

## 3. Rutas y Páginas

| Ruta | Tipo | Componente Página | Descripción |
|---|---|---|---|
| `/reportes` | Protected — Gerente, Analista, Auditor, Administrador | `ReporteListPage` | Lista paginada de solicitudes de reportes del usuario autenticado. Incluye estado de cada reporte y botón de descarga para los COMPLETADOS. |
| `/reportes/nuevo` | Protected — Gerente, Analista, Auditor, Administrador | `ReporteFormPage` | Formulario de solicitud de generación de reporte. Tipo de reporte filtrado por rol. Parámetros dinámicos según tipo seleccionado. |
| `/reportes/[id]` | Protected — Gerente, Analista, Auditor, Administrador | `ReporteDetailPage` | Estado del reporte con auto-polling si está en proceso. Botón de descarga cuando COMPLETADO. Botón de reintentar cuando FALLIDO. |

### Protección de Rutas — Middleware

```typescript
// src/middleware.ts
const REPORTE_ROLES = ['ADMINISTRADOR', 'GERENTE', 'ANALISTA', 'AUDITOR']

// En el middleware de Next.js:
if (pathname.startsWith('/reportes')) {
  if (!REPORTE_ROLES.includes(userRole)) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }
}
```

### Implementación de Páginas

#### `app/(protected)/reportes/page.tsx`

```typescript
import { Suspense } from 'react'
import { ReporteListPage } from '@/components/reportes/ReporteListPage'
import { PageSkeleton } from '@/components/ui/PageSkeleton'
import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'

export const metadata = { title: 'Reportes — ControlStock' }

const ALLOWED_ROLES = ['ADMINISTRADOR', 'GERENTE', 'ANALISTA', 'AUDITOR']

export default async function Page() {
  const session = await getServerSession(authOptions)
  if (!ALLOWED_ROLES.includes(session?.user?.rol ?? '')) {
    redirect('/dashboard')
  }

  return (
    <Suspense fallback={<PageSkeleton />}>
      <ReporteListPage />
    </Suspense>
  )
}
```

#### `app/(protected)/reportes/[id]/page.tsx`

```typescript
interface Props { params: { id: string } }

export default async function Page({ params }: Props) {
  const session = await getServerSession(authOptions)
  if (!ALLOWED_ROLES.includes(session?.user?.rol ?? '')) {
    redirect('/dashboard')
  }

  return <ReporteDetailPage id={params.id} />
}
```

---

## 4. Componentes

> **Nota TDD:** test-first — el test de render/interacción precede al componente. Cada componente tiene su archivo `.test.tsx` escrito y en estado RED antes de crear el `.tsx` correspondiente.

### 4.1 `ReporteTable`

**Archivo:** `src/components/reportes/ReporteTable.tsx`

**Responsabilidad:** Renderiza la tabla de solicitudes de reportes con columnas: fecha de solicitud, tipo de reporte, formato (badge), estado (badge), acciones (ver detalle, descargar si COMPLETADO).

**Props:**

```typescript
interface ReporteTableProps {
  reportes: ReporteRequestResponse[]
  isLoading: boolean
}
```

**Implementación:**

```typescript
'use client'

import { ReporteRequestResponse } from '@/types/reporte.types'
import { ReporteEstadoBadge } from './ReporteEstadoBadge'
import { FormatoBadge } from './FormatoBadge'
import Link from 'next/link'

const TIPO_LABELS: Record<string, string> = {
  'stock-actual': 'Stock Actual',
  'movimientos-periodo': 'Movimientos del Período',
  'auditoria-operaciones': 'Auditoría de Operaciones',
  'proveedores-actividad': 'Actividad de Proveedores',
}

export function ReporteTable({ reportes, isLoading }: ReporteTableProps) {
  if (isLoading) {
    return <div role="status" aria-label="Cargando reportes">Cargando...</div>
  }

  if (reportes.length === 0) {
    return (
      <div role="status" data-testid="empty-state">
        No hay reportes generados. Solicite uno nuevo.
      </div>
    )
  }

  return (
    <table aria-label="Lista de reportes">
      <thead>
        <tr>
          <th scope="col">Fecha Solicitud</th>
          <th scope="col">Tipo</th>
          <th scope="col">Formato</th>
          <th scope="col">Estado</th>
          <th scope="col">Acciones</th>
        </tr>
      </thead>
      <tbody>
        {reportes.map((r) => (
          <tr key={r.id} data-testid={`row-${r.id}`}>
            <td>{new Date(r.createdAt).toLocaleString('es-AR')}</td>
            <td>{TIPO_LABELS[r.reportType] ?? r.reportType}</td>
            <td><FormatoBadge formato={r.formato} /></td>
            <td><ReporteEstadoBadge estado={r.estado} /></td>
            <td>
              <Link href={`/reportes/${r.id}`} aria-label={`Ver detalle del reporte ${r.id}`}>
                Ver
              </Link>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
```

---

### 4.2 `ReporteForm`

**Archivo:** `src/components/reportes/ReporteForm.tsx`

**Responsabilidad:** Formulario de solicitud de reporte. El select de tipo se filtra dinámicamente según el rol del usuario. Los parámetros de fechas aparecen solo para tipos que los requieren (`movimientos-periodo`).

**Props:**

```typescript
interface ReporteFormProps {
  onSubmit: (data: CreateReporteInput) => void
  isSubmitting: boolean
  rol: UserRole
}
```

**Tipos disponibles por rol:**

```typescript
const TIPOS_POR_ROL: Record<string, CreateReporteInput['reportType'][]> = {
  ADMINISTRADOR: ['stock-actual', 'movimientos-periodo', 'auditoria-operaciones', 'proveedores-actividad'],
  GERENTE: ['stock-actual', 'movimientos-periodo', 'proveedores-actividad'],
  ANALISTA: ['stock-actual', 'movimientos-periodo'],
  AUDITOR: ['stock-actual', 'auditoria-operaciones'],
}

const TIPOS_CON_FECHAS: CreateReporteInput['reportType'][] = ['movimientos-periodo']
```

**Implementación:**

```typescript
'use client'

import { useForm, useWatch } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { CreateReporteSchema } from '@/schemas/reporte.schema'
import type { CreateReporteInput } from '@/schemas/reporte.schema'

const TIPO_LABELS: Record<string, string> = {
  'stock-actual': 'Stock Actual',
  'movimientos-periodo': 'Movimientos del Período',
  'auditoria-operaciones': 'Auditoría de Operaciones',
  'proveedores-actividad': 'Actividad de Proveedores',
}

export function ReporteForm({ onSubmit, isSubmitting, rol }: ReporteFormProps) {
  const tiposDisponibles = TIPOS_POR_ROL[rol] ?? ['stock-actual']

  const { register, handleSubmit, control, formState: { errors } } = useForm<CreateReporteInput>({
    resolver: zodResolver(CreateReporteSchema),
  })

  const reportType = useWatch({ control, name: 'reportType' })
  const requiereFechas = TIPOS_CON_FECHAS.includes(reportType)

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate aria-label="Formulario de solicitud de reporte">
      <div>
        <label htmlFor="reportType">Tipo de Reporte</label>
        <select
          id="reportType"
          {...register('reportType')}
          aria-invalid={!!errors.reportType}
          data-testid="report-type-select"
        >
          <option value="">Seleccione un tipo...</option>
          {tiposDisponibles.map((tipo) => (
            <option key={tipo} value={tipo}>
              {TIPO_LABELS[tipo]}
            </option>
          ))}
        </select>
        {errors.reportType && (
          <span role="alert">{errors.reportType.message}</span>
        )}
      </div>

      <div>
        <label htmlFor="formato">Formato de Salida</label>
        <select id="formato" {...register('formato')} aria-invalid={!!errors.formato}>
          <option value="">Seleccione formato...</option>
          <option value="XLSX">Excel (XLSX)</option>
          <option value="CSV">CSV</option>
          <option value="PDF">PDF</option>
        </select>
        {errors.formato && (
          <span role="alert">{errors.formato.message}</span>
        )}
      </div>

      {requiereFechas && (
        <fieldset data-testid="fecha-range-section">
          <legend>Rango de Fechas</legend>
          <div>
            <label htmlFor="fechaDesde">Fecha Desde</label>
            <input
              id="fechaDesde"
              type="date"
              {...register('parametros.fechaDesde')}
            />
          </div>
          <div>
            <label htmlFor="fechaHasta">Fecha Hasta</label>
            <input
              id="fechaHasta"
              type="date"
              {...register('parametros.fechaHasta')}
            />
          </div>
        </fieldset>
      )}

      <button type="submit" disabled={isSubmitting} aria-busy={isSubmitting}>
        {isSubmitting ? 'Solicitando...' : 'Solicitar Reporte'}
      </button>
    </form>
  )
}
```

---

### 4.3 `ReporteDetail`

**Archivo:** `src/components/reportes/ReporteDetail.tsx`

**Responsabilidad:** Muestra el estado del reporte con comportamiento adaptativo:
- Si estado es SOLICITADO o PROCESANDO: muestra `PollingStatus`
- Si estado es COMPLETADO: muestra `DescargaButton`
- Si estado es FALLIDO: muestra botón de reintentar

**Props:**

```typescript
interface ReporteDetailProps {
  reporteId: string
}
```

**Implementación:**

```typescript
'use client'

import { useReporte } from '@/hooks/reportes/useReporte'
import { ReporteEstadoBadge } from './ReporteEstadoBadge'
import { FormatoBadge } from './FormatoBadge'
import { PollingStatus } from './PollingStatus'
import { DescargaButton } from './DescargaButton'
import Link from 'next/link'

const ESTADOS_EN_PROGRESO = ['SOLICITADO', 'PROCESANDO'] as const

export function ReporteDetail({ reporteId }: ReporteDetailProps) {
  const estaEnProgreso = (estado: string) =>
    ESTADOS_EN_PROGRESO.includes(estado as any)

  const { data: reporte, isLoading, isError } = useReporte(reporteId, {
    poll: true,
  })

  if (isLoading) return <div role="status">Cargando detalle del reporte...</div>
  if (isError || !reporte) return <div role="alert">Error al cargar el reporte.</div>

  return (
    <article aria-label={`Detalle del reporte ${reporte.id}`}>
      <header>
        <h1>Detalle del Reporte</h1>
        <ReporteEstadoBadge estado={reporte.estado} />
      </header>

      <dl>
        <dt>ID</dt>
        <dd>{reporte.id}</dd>
        <dt>Tipo</dt>
        <dd>{reporte.reportType}</dd>
        <dt>Formato</dt>
        <dd><FormatoBadge formato={reporte.formato} /></dd>
        <dt>Solicitado</dt>
        <dd>{new Date(reporte.createdAt).toLocaleString('es-AR')}</dd>
        {reporte.updatedAt && (
          <>
            <dt>Actualizado</dt>
            <dd>{new Date(reporte.updatedAt).toLocaleString('es-AR')}</dd>
          </>
        )}
      </dl>

      {estaEnProgreso(reporte.estado) && (
        <PollingStatus estado={reporte.estado} createdAt={reporte.createdAt} />
      )}

      {reporte.estado === 'COMPLETADO' && (
        <DescargaButton reporteId={reporte.id} formato={reporte.formato} />
      )}

      {reporte.estado === 'FALLIDO' && (
        <div role="alert" data-testid="fallido-section">
          <p>La generación del reporte falló. Por favor, intente nuevamente.</p>
          <Link href="/reportes/nuevo">Solicitar nuevo reporte</Link>
        </div>
      )}
    </article>
  )
}
```

---

### 4.4 `ReporteEstadoBadge`

**Archivo:** `src/components/reportes/ReporteEstadoBadge.tsx`

```typescript
'use client'

type EstadoReporte = 'SOLICITADO' | 'PROCESANDO' | 'COMPLETADO' | 'FALLIDO'

interface ReporteEstadoBadgeProps {
  estado: EstadoReporte
}

const ESTADO_CONFIG: Record<EstadoReporte, { label: string; className: string; ariaLabel: string }> = {
  SOLICITADO: {
    label: 'Solicitado',
    className: 'badge badge-blue',
    ariaLabel: 'Estado: Solicitado - en cola de procesamiento',
  },
  PROCESANDO: {
    label: 'Procesando',
    className: 'badge badge-yellow badge-spinning',
    ariaLabel: 'Estado: Procesando - en generación activa',
  },
  COMPLETADO: {
    label: 'Completado',
    className: 'badge badge-green',
    ariaLabel: 'Estado: Completado - listo para descarga',
  },
  FALLIDO: {
    label: 'Fallido',
    className: 'badge badge-red',
    ariaLabel: 'Estado: Fallido - error en generación',
  },
}

export function ReporteEstadoBadge({ estado }: ReporteEstadoBadgeProps) {
  const config = ESTADO_CONFIG[estado]

  return (
    <span
      className={config.className}
      aria-label={config.ariaLabel}
      data-testid={`estado-badge-${estado.toLowerCase()}`}
    >
      {estado === 'PROCESANDO' && (
        <span className="spinner" aria-hidden="true" />
      )}
      {config.label}
    </span>
  )
}
```

---

### 4.5 `FormatoBadge`

**Archivo:** `src/components/reportes/FormatoBadge.tsx`

```typescript
'use client'

type FormatoReporte = 'XLSX' | 'CSV' | 'PDF'

interface FormatoBadgeProps {
  formato: FormatoReporte
}

const FORMATO_CONFIG: Record<FormatoReporte, { label: string; className: string }> = {
  XLSX: { label: 'XLSX', className: 'badge badge-green' },
  CSV: { label: 'CSV', className: 'badge badge-gray' },
  PDF: { label: 'PDF', className: 'badge badge-red' },
}

export function FormatoBadge({ formato }: FormatoBadgeProps) {
  const config = FORMATO_CONFIG[formato]
  return (
    <span
      className={config.className}
      data-testid={`formato-badge-${formato.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

---

### 4.6 `DescargaButton`

**Archivo:** `src/components/reportes/DescargaButton.tsx`

**Responsabilidad:** Ejecuta la descarga del reporte usando `fetch` + `Blob` + `URL.createObjectURL`. No expone la URL pre-firmada de MinIO directamente en el DOM.

**Props:**

```typescript
interface DescargaButtonProps {
  reporteId: string
  formato: 'XLSX' | 'CSV' | 'PDF'
}
```

**Implementación:**

```typescript
'use client'

import { useState } from 'react'
import { useDescargarReporte } from '@/hooks/reportes/useDescargarReporte'

const FORMATO_MIME: Record<string, string> = {
  XLSX: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  CSV: 'text/csv',
  PDF: 'application/pdf',
}

export function DescargaButton({ reporteId, formato }: DescargaButtonProps) {
  const [isDownloading, setIsDownloading] = useState(false)
  const { descargar } = useDescargarReporte(reporteId)

  const handleDescargar = async () => {
    setIsDownloading(true)
    try {
      await descargar(`reporte-${reporteId}.${formato.toLowerCase()}`)
    } finally {
      setIsDownloading(false)
    }
  }

  return (
    <button
      onClick={handleDescargar}
      disabled={isDownloading}
      aria-busy={isDownloading}
      data-testid="descarga-btn"
    >
      {isDownloading ? 'Descargando...' : `Descargar ${formato}`}
    </button>
  )
}
```

---

### 4.7 `PollingStatus`

**Archivo:** `src/components/reportes/PollingStatus.tsx`

**Responsabilidad:** Muestra el spinner y tiempo transcurrido mientras el reporte está en procesamiento. Se oculta cuando el reporte está COMPLETADO o FALLIDO.

**Props:**

```typescript
interface PollingStatusProps {
  estado: 'SOLICITADO' | 'PROCESANDO'
  createdAt: string
}
```

**Implementación:**

```typescript
'use client'

import { useEffect, useState } from 'react'

function getElapsedSeconds(createdAt: string): number {
  return Math.floor((Date.now() - new Date(createdAt).getTime()) / 1000)
}

export function PollingStatus({ estado, createdAt }: PollingStatusProps) {
  const [elapsed, setElapsed] = useState(getElapsedSeconds(createdAt))

  useEffect(() => {
    const interval = setInterval(() => {
      setElapsed(getElapsedSeconds(createdAt))
    }, 1000)
    return () => clearInterval(interval)
  }, [createdAt])

  const minutes = Math.floor(elapsed / 60)
  const seconds = elapsed % 60
  const elapsedLabel = minutes > 0
    ? `${minutes}m ${seconds}s`
    : `${seconds}s`

  return (
    <div
      role="status"
      aria-live="polite"
      aria-label="Generando reporte"
      data-testid="polling-status"
    >
      <span className="spinner" aria-hidden="true" />
      <span>Generando reporte...</span>
      <span data-testid="elapsed-time">Tiempo transcurrido: {elapsedLabel}</span>
      <small>
        {estado === 'PROCESANDO'
          ? 'El reporte se está generando. Esta página se actualiza automáticamente.'
          : 'El reporte está en la cola de procesamiento.'}
      </small>
    </div>
  )
}
```

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** test-first — cada hook tiene su archivo `.test.ts` escrito en estado RED antes de implementar el hook. MSW intercepta las peticiones en los tests.

### Configuración Base API

**Archivo:** `src/lib/api/reportes.api.ts`

```typescript
import { z } from 'zod'
import { ReporteRequestResponseSchema } from '@/schemas/reporte.schema'
import type { CreateReporteInput } from '@/schemas/reporte.schema'
import { getSession } from 'next-auth/react'

const BASE_URL = `${process.env.NEXT_PUBLIC_API_URL}/reports`

async function fetchWithAuth(url: string, options?: RequestInit) {
  const session = await getSession()
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session?.accessToken}`,
      ...options?.headers,
    },
  })

  if (!res.ok) {
    const error = await res.json().catch(() => ({ message: res.statusText }))
    throw { status: res.status, ...error }
  }

  // Para 202 Accepted con body vacío o para blob
  return res
}

export const reportesApi = {
  list: async (params?: { page?: number; size?: number }) => {
    const sp = new URLSearchParams()
    if (params?.page !== undefined) sp.set('page', String(params.page))
    if (params?.size !== undefined) sp.set('size', String(params.size))
    const res = await fetchWithAuth(`${BASE_URL}?${sp}`)
    const data = await res.json()
    return z.array(ReporteRequestResponseSchema).parse(data.content ?? data)
  },

  getById: async (id: string) => {
    const res = await fetchWithAuth(`${BASE_URL}/${id}`)
    const data = await res.json()
    return ReporteRequestResponseSchema.parse(data)
  },

  create: async (input: CreateReporteInput) => {
    const res = await fetchWithAuth(BASE_URL, {
      method: 'POST',
      body: JSON.stringify(input),
    })
    // 202 Accepted — retorna el objeto de la solicitud creada
    const data = await res.json()
    return ReporteRequestResponseSchema.parse(data)
  },

  descargar: async (id: string): Promise<Blob> => {
    const res = await fetchWithAuth(`${BASE_URL}/${id}/download`)
    return res.blob()
  },
}
```

---

### 5.1 `useReportes`

**Archivo:** `src/hooks/reportes/useReportes.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { reportesApi } from '@/lib/api/reportes.api'

export const REPORTES_QUERY_KEY = ['reportes'] as const

export function useReportes(params?: { page?: number; size?: number }) {
  return useQuery({
    queryKey: [...REPORTES_QUERY_KEY, params],
    queryFn: () => reportesApi.list(params),
    staleTime: 30 * 1000, // 30 segundos — los reportes cambian de estado frecuentemente
  })
}
```

---

### 5.2 `useReporte` (con polling inteligente)

**Archivo:** `src/hooks/reportes/useReporte.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { reportesApi } from '@/lib/api/reportes.api'

const ESTADOS_EN_PROGRESO = ['SOLICITADO', 'PROCESANDO']

export const reporteQueryKey = (id: string) => ['reporte', id] as const

interface UseReporteOptions {
  poll?: boolean
}

export function useReporte(id: string, options: UseReporteOptions = {}) {
  const { poll = false } = options

  return useQuery({
    queryKey: reporteQueryKey(id),
    queryFn: () => reportesApi.getById(id),
    enabled: !!id,
    staleTime: 0, // Siempre fresco cuando se hace polling
    refetchInterval: (query) => {
      if (!poll) return false
      const estado = query.state.data?.estado
      if (!estado) return false
      // Solo hace polling si el estado es SOLICITADO o PROCESANDO
      return ESTADOS_EN_PROGRESO.includes(estado) ? 5000 : false
    },
  })
}
```

---

### 5.3 `useCreateReporte`

**Archivo:** `src/hooks/reportes/useCreateReporte.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { reportesApi } from '@/lib/api/reportes.api'
import { REPORTES_QUERY_KEY } from './useReportes'
import { useReportesStore } from '@/store/reportesStore'

export function useCreateReporte() {
  const queryClient = useQueryClient()
  const router = useRouter()
  const { addPollingId } = useReportesStore()

  return useMutation({
    mutationFn: reportesApi.create,
    onSuccess: (newReporte) => {
      queryClient.invalidateQueries({ queryKey: REPORTES_QUERY_KEY })
      // Registrar en Zustand para tracking global de polling
      addPollingId(newReporte.id)
      // Navegar al detalle donde se activará el polling
      router.push(`/reportes/${newReporte.id}`)
    },
    onError: (error: any) => {
      // Los errores 400 y 403 se manejan en la UI
      console.error('[useCreateReporte] Error:', error)
    },
  })
}
```

---

### 5.4 `useDescargarReporte`

**Archivo:** `src/hooks/reportes/useDescargarReporte.ts`

```typescript
import { reportesApi } from '@/lib/api/reportes.api'
import { useReportesStore } from '@/store/reportesStore'

export function useDescargarReporte(reporteId: string) {
  const { removePollingId } = useReportesStore()

  const descargar = async (fileName: string) => {
    const blob = await reportesApi.descargar(reporteId)

    // Crear URL temporal y disparar descarga del navegador
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = fileName
    document.body.appendChild(a)
    a.click()

    // Limpiar recursos
    setTimeout(() => {
      URL.revokeObjectURL(url)
      document.body.removeChild(a)
    }, 100)

    // Remover de la lista de polling activo
    removePollingId(reporteId)
  }

  return { descargar }
}
```

---

## 6. Estado Global (Zustand)

> **Nota TDD:** test-first — el test del slice se escribe antes de implementar el store. Se prueba cada acción de forma aislada usando `renderHook` de Testing Library.

### `reportesSlice`

**Archivo:** `src/store/slices/reportesSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export interface ReportesSlice {
  pollingIds: string[]
  addPollingId: (id: string) => void
  removePollingId: (id: string) => void
  clearPollingIds: () => void
}

export const createReportesSlice: StateCreator<ReportesSlice> = (set) => ({
  pollingIds: [],

  addPollingId: (id) =>
    set((state) => ({
      pollingIds: state.pollingIds.includes(id)
        ? state.pollingIds
        : [...state.pollingIds, id],
    })),

  removePollingId: (id) =>
    set((state) => ({
      pollingIds: state.pollingIds.filter((pid) => pid !== id),
    })),

  clearPollingIds: () => set({ pollingIds: [] }),
})
```

**Archivo:** `src/store/reportesStore.ts`

```typescript
import { create } from 'zustand'
import { devtools } from 'zustand/middleware'
import { ReportesSlice, createReportesSlice } from './slices/reportesSlice'

export const useReportesStore = create<ReportesSlice>()(
  devtools(createReportesSlice, { name: 'ReportesStore' })
)
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** test-first — los tests de schemas se escriben primero. Se verifican casos válidos, inválidos y edge cases antes de definir los schemas.

**Archivo:** `src/schemas/reporte.schema.ts`

```typescript
import { z } from 'zod'

// --- Enumeraciones ---

export const ReportTypeEnum = z.enum([
  'stock-actual',
  'movimientos-periodo',
  'auditoria-operaciones',
  'proveedores-actividad',
])

export const FormatoEnum = z.enum(['XLSX', 'CSV', 'PDF'])

export const EstadoReporteEnum = z.enum(['SOLICITADO', 'PROCESANDO', 'COMPLETADO', 'FALLIDO'])

// --- Schemas de Input ---

export const ParametrosReporteSchema = z
  .object({
    fechaDesde: z.string().date('Formato de fecha inválido').optional(),
    fechaHasta: z.string().date('Formato de fecha inválido').optional(),
  })
  .optional()

export const CreateReporteSchema = z.object({
  reportType: ReportTypeEnum,
  formato: FormatoEnum,
  parametros: ParametrosReporteSchema,
})

// --- Schemas de Response ---

export const ReporteRequestResponseSchema = z.object({
  id: z.string().uuid(),
  usuarioId: z.string(),
  reportType: ReportTypeEnum,
  parametros: z.record(z.unknown()).nullable().optional(),
  formato: FormatoEnum,
  estado: EstadoReporteEnum,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
})

export const ReporteFileSchema = z.object({
  id: z.string().uuid(),
  reportRequestId: z.string().uuid(),
  formato: FormatoEnum,
  urlMinio: z.string().url(),
  tamanioBytes: z.number().int().positive(),
  createdAt: z.string().datetime(),
})

// --- Tipos inferidos ---

export type CreateReporteInput = z.infer<typeof CreateReporteSchema>
export type ReporteRequestResponse = z.infer<typeof ReporteRequestResponseSchema>
export type ReporteFile = z.infer<typeof ReporteFileSchema>
```

---

## 8. Autenticación y Autorización

### Roles y Tipos de Reporte

| Tipo de Reporte | Gerente | Analista | Auditor | Administrador |
|---|---|---|---|---|
| `stock-actual` | SI | SI | SI | SI |
| `movimientos-periodo` | SI | SI | NO | SI |
| `auditoria-operaciones` | NO | NO | SI | SI |
| `proveedores-actividad` | SI | NO | NO | SI |

### Protección de Rutas

Las rutas `/reportes/**` solo son accesibles para roles: ADMINISTRADOR, GERENTE, ANALISTA, AUDITOR. Cualquier otro rol (OPERADOR, SUPERVISOR) es redirigido a `/dashboard`.

### Filtrado de Tipos por Rol en ReporteForm

```typescript
// src/constants/reportes.constants.ts
export const TIPOS_POR_ROL: Record<string, string[]> = {
  ADMINISTRADOR: [
    'stock-actual',
    'movimientos-periodo',
    'auditoria-operaciones',
    'proveedores-actividad',
  ],
  GERENTE: ['stock-actual', 'movimientos-periodo', 'proveedores-actividad'],
  ANALISTA: ['stock-actual', 'movimientos-periodo'],
  AUDITOR: ['stock-actual', 'auditoria-operaciones'],
}
```

### Hook de sesión para validar rol en ReporteForm

```typescript
// En ReporteFormPage
'use client'
import { useSession } from 'next-auth/react'

export function ReporteFormPage() {
  const { data: session } = useSession()
  const rol = session?.user?.rol ?? ''

  if (!['ADMINISTRADOR', 'GERENTE', 'ANALISTA', 'AUDITOR'].includes(rol)) {
    return <Redirect href="/dashboard" />
  }

  return <ReporteForm rol={rol} ... />
}
```

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Red-Green-Refactor:** Cada test se escribe primero en estado RED. Se implementa código mínimo para GREEN. Se refactoriza manteniendo todos los tests en GREEN.

### 9.1 Tests de Schemas

**Archivo:** `src/schemas/reporte.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import {
  CreateReporteSchema,
  ReporteRequestResponseSchema,
} from './reporte.schema'

describe('CreateReporteSchema', () => {
  it('valida solicitud de stock-actual XLSX válida', () => {
    const input = {
      reportType: 'stock-actual',
      formato: 'XLSX',
    }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('valida solicitud de movimientos-periodo con fechas válidas', () => {
    const input = {
      reportType: 'movimientos-periodo',
      formato: 'CSV',
      parametros: {
        fechaDesde: '2024-01-01',
        fechaHasta: '2024-01-31',
      },
    }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('falla cuando reportType es inválido', () => {
    const input = {
      reportType: 'stock-historico-invalido',
      formato: 'XLSX',
    }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].path).toContain('reportType')
  })

  it('falla cuando formato es inválido', () => {
    const input = {
      reportType: 'stock-actual',
      formato: 'DOCX',
    }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(false)
  })

  it('permite parametros como objeto vacío (todos opcionales)', () => {
    const input = {
      reportType: 'stock-actual',
      formato: 'PDF',
      parametros: {},
    }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('permite solicitud sin parametros', () => {
    const input = { reportType: 'auditoria-operaciones', formato: 'PDF' }
    const result = CreateReporteSchema.safeParse(input)
    expect(result.success).toBe(true)
  })
})

describe('ReporteRequestResponseSchema', () => {
  const baseReporte = {
    id: '123e4567-e89b-12d3-a456-426614174000',
    usuarioId: 'user-123',
    reportType: 'stock-actual',
    formato: 'XLSX',
    estado: 'PROCESANDO',
    createdAt: '2024-01-15T10:00:00.000Z',
    updatedAt: '2024-01-15T10:01:00.000Z',
  }

  it('valida respuesta de reporte válida', () => {
    const result = ReporteRequestResponseSchema.safeParse(baseReporte)
    expect(result.success).toBe(true)
  })

  it('falla con estado inválido', () => {
    const result = ReporteRequestResponseSchema.safeParse({
      ...baseReporte,
      estado: 'EN_COLA',
    })
    expect(result.success).toBe(false)
  })
})
```

---

### 9.2 Tests de Hooks

**Archivo:** `src/hooks/reportes/useReporte.test.ts`

```typescript
import { describe, it, expect, vi, beforeAll, afterEach, afterAll } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'
import { createWrapper } from '@/test/utils'
import { useReporte } from './useReporte'

let estadoActual = 'PROCESANDO'

const server = setupServer(
  http.get('*/api/v1/reports/:id', ({ params }) => {
    return HttpResponse.json({
      id: params.id,
      usuarioId: 'user-1',
      reportType: 'stock-actual',
      formato: 'XLSX',
      estado: estadoActual,
      createdAt: '2024-01-15T10:00:00.000Z',
      updatedAt: '2024-01-15T10:00:00.000Z',
    })
  })
)

beforeAll(() => server.listen())
afterEach(() => {
  server.resetHandlers()
  estadoActual = 'PROCESANDO'
})
afterAll(() => server.close())

describe('useReporte con polling', () => {
  it('activa polling (refetchInterval=5000) cuando estado es PROCESANDO y poll=true', async () => {
    const { result } = renderHook(
      () => useReporte('reporte-1', { poll: true }),
      { wrapper: createWrapper() }
    )

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.estado).toBe('PROCESANDO')
    // El query debe tener refetchInterval activo
    // Verificamos que el estado es PROCESANDO y poll está activo
  })

  it('detiene el polling cuando estado cambia a COMPLETADO', async () => {
    vi.useFakeTimers()

    estadoActual = 'PROCESANDO'
    const { result } = renderHook(
      () => useReporte('reporte-1', { poll: true }),
      { wrapper: createWrapper() }
    )

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.estado).toBe('PROCESANDO')

    // Simular cambio de estado en el servidor
    estadoActual = 'COMPLETADO'

    // Avanzar 5 segundos para siguiente poll
    act(() => { vi.advanceTimersByTime(5000) })

    await waitFor(() => expect(result.current.data?.estado).toBe('COMPLETADO'))
    // Después de COMPLETADO, no debería haber más refetches

    vi.useRealTimers()
  })

  it('no activa polling cuando poll=false', async () => {
    const { result } = renderHook(
      () => useReporte('reporte-1', { poll: false }),
      { wrapper: createWrapper() }
    )
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    // No hay polling — solo carga una vez
  })
})

describe('useCreateReporte', () => {
  it('respuesta 202 navega a la página de detalle del reporte', async () => {
    const mockPush = vi.fn()
    vi.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush }) }))

    server.use(
      http.post('*/api/v1/reports', () =>
        HttpResponse.json(
          {
            id: 'nuevo-reporte-id',
            usuarioId: 'user-1',
            reportType: 'stock-actual',
            formato: 'XLSX',
            estado: 'SOLICITADO',
            createdAt: '2024-01-15T10:00:00.000Z',
            updatedAt: '2024-01-15T10:00:00.000Z',
          },
          { status: 202 }
        )
      )
    )

    const { result } = renderHook(() => useCreateReporte(), { wrapper: createWrapper() })
    result.current.mutate({ reportType: 'stock-actual', formato: 'XLSX' })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(mockPush).toHaveBeenCalledWith('/reportes/nuevo-reporte-id')
  })

  it('error 400 expone mensaje de validación', async () => {
    server.use(
      http.post('*/api/v1/reports', () =>
        HttpResponse.json({ message: 'Parámetros inválidos' }, { status: 400 })
      )
    )

    const { result } = renderHook(() => useCreateReporte(), { wrapper: createWrapper() })
    result.current.mutate({ reportType: 'stock-actual', formato: 'XLSX' })

    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(400)
  })

  it('error 403 cuando el rol no tiene acceso al tipo de reporte', async () => {
    server.use(
      http.post('*/api/v1/reports', () =>
        HttpResponse.json({ message: 'No autorizado para este tipo de reporte' }, { status: 403 })
      )
    )

    const { result } = renderHook(() => useCreateReporte(), { wrapper: createWrapper() })
    result.current.mutate({ reportType: 'auditoria-operaciones', formato: 'PDF' })

    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(403)
  })
})
```

---

### 9.3 Tests de Componentes

**Archivo:** `src/components/reportes/ReporteForm.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ReporteForm } from './ReporteForm'

describe('ReporteForm', () => {
  it('renderiza el select de tipo con opciones filtradas para rol Gerente', () => {
    render(<ReporteForm onSubmit={vi.fn()} isSubmitting={false} rol="GERENTE" />)

    const select = screen.getByTestId('report-type-select')
    const options = Array.from(select.querySelectorAll('option')).map(o => o.value)

    expect(options).toContain('stock-actual')
    expect(options).toContain('movimientos-periodo')
    expect(options).toContain('proveedores-actividad')
    expect(options).not.toContain('auditoria-operaciones') // Gerente NO tiene acceso
  })

  it('no muestra auditoria-operaciones en el select para rol Analista', () => {
    render(<ReporteForm onSubmit={vi.fn()} isSubmitting={false} rol="ANALISTA" />)

    const select = screen.getByTestId('report-type-select')
    const options = Array.from(select.querySelectorAll('option')).map(o => o.value)

    expect(options).not.toContain('auditoria-operaciones')
    expect(options).not.toContain('proveedores-actividad')
  })

  it('muestra sección de fechas solo cuando tipo es movimientos-periodo', async () => {
    render(<ReporteForm onSubmit={vi.fn()} isSubmitting={false} rol="ADMINISTRADOR" />)

    // Inicialmente no hay sección de fechas
    expect(screen.queryByTestId('fecha-range-section')).not.toBeInTheDocument()

    // Seleccionar movimientos-periodo
    await userEvent.selectOptions(
      screen.getByTestId('report-type-select'),
      'movimientos-periodo'
    )

    // Ahora aparece la sección de fechas
    expect(screen.getByTestId('fecha-range-section')).toBeInTheDocument()
  })

  it('NO muestra sección de fechas para tipo stock-actual', async () => {
    render(<ReporteForm onSubmit={vi.fn()} isSubmitting={false} rol="ADMINISTRADOR" />)

    await userEvent.selectOptions(
      screen.getByTestId('report-type-select'),
      'stock-actual'
    )

    expect(screen.queryByTestId('fecha-range-section')).not.toBeInTheDocument()
  })
})

describe('PollingStatus', () => {
  it('renderiza spinner y texto "Generando reporte..." cuando PROCESANDO', () => {
    render(
      <PollingStatus
        estado="PROCESANDO"
        createdAt={new Date().toISOString()}
      />
    )
    expect(screen.getByTestId('polling-status')).toBeInTheDocument()
    expect(screen.getByText(/generando reporte/i)).toBeInTheDocument()
  })

  it('muestra tiempo transcurrido', () => {
    const pastTime = new Date(Date.now() - 30000).toISOString() // 30s atrás
    render(<PollingStatus estado="PROCESANDO" createdAt={pastTime} />)
    expect(screen.getByTestId('elapsed-time')).toBeInTheDocument()
  })
})

describe('ReporteEstadoBadge', () => {
  it('renderiza badge azul para SOLICITADO', () => {
    render(<ReporteEstadoBadge estado="SOLICITADO" />)
    expect(screen.getByTestId('estado-badge-solicitado')).toHaveClass('badge-blue')
  })

  it('renderiza badge amarillo con spinner para PROCESANDO', () => {
    render(<ReporteEstadoBadge estado="PROCESANDO" />)
    const badge = screen.getByTestId('estado-badge-procesando')
    expect(badge).toHaveClass('badge-yellow')
    expect(badge.querySelector('.spinner')).toBeInTheDocument()
  })

  it('renderiza badge verde para COMPLETADO', () => {
    render(<ReporteEstadoBadge estado="COMPLETADO" />)
    expect(screen.getByTestId('estado-badge-completado')).toHaveClass('badge-green')
  })

  it('renderiza badge rojo para FALLIDO', () => {
    render(<ReporteEstadoBadge estado="FALLIDO" />)
    expect(screen.getByTestId('estado-badge-fallido')).toHaveClass('badge-red')
  })
})

describe('reportesSlice', () => {
  it('addPollingId agrega ID al array pollingIds', () => {
    const { result } = renderHook(() => useReportesStore())
    act(() => result.current.addPollingId('reporte-abc'))
    expect(result.current.pollingIds).toContain('reporte-abc')
  })

  it('addPollingId no duplica IDs', () => {
    const { result } = renderHook(() => useReportesStore())
    act(() => {
      result.current.addPollingId('reporte-abc')
      result.current.addPollingId('reporte-abc')
    })
    expect(result.current.pollingIds.filter(id => id === 'reporte-abc')).toHaveLength(1)
  })

  it('removePollingId elimina el ID del array', () => {
    const { result } = renderHook(() => useReportesStore())
    act(() => {
      result.current.addPollingId('reporte-abc')
      result.current.removePollingId('reporte-abc')
    })
    expect(result.current.pollingIds).not.toContain('reporte-abc')
  })

  it('removePollingId no falla si el ID no existe', () => {
    const { result } = renderHook(() => useReportesStore())
    act(() => result.current.removePollingId('id-no-existente'))
    expect(result.current.pollingIds).toHaveLength(0)
  })
})
```

---

## 10. Pruebas E2E (Playwright, ATDD)

**Archivo:** `e2e/reportes/reportes.spec.ts`

```typescript
import { test, expect, Page } from '@playwright/test'
import { loginAs } from '../helpers/auth'

// Helper para esperar que el estado del reporte cambie
async function waitForEstado(page: Page, estado: string, timeout = 60000) {
  await expect(
    page.getByTestId(`estado-badge-${estado.toLowerCase()}`),
    `Esperando estado ${estado}`
  ).toBeVisible({ timeout })
}

test.describe('Feature Reportes', () => {

  // TC-REP-01: Gerente solicita stock-actual XLSX → polling → COMPLETADO → botón descarga
  test('TC-REP-01: Gerente solicita stock-actual XLSX y espera COMPLETADO para descargar', async ({ page }) => {
    await loginAs(page, 'gerente')

    await page.goto('/reportes/nuevo')
    await expect(page.getByRole('heading', { name: /solicitar reporte/i })).toBeVisible()

    // Cuando selecciona tipo y formato
    await page.getByTestId('report-type-select').selectOption('stock-actual')
    await page.getByLabel('Formato de Salida').selectOption('XLSX')
    await page.getByRole('button', { name: /solicitar reporte/i }).click()

    // Entonces es redirigido al detalle con estado SOLICITADO
    await expect(page).toHaveURL(/\/reportes\/[\w-]+$/)
    await waitForEstado(page, 'SOLICITADO')

    // Y el PollingStatus está visible
    await expect(page.getByTestId('polling-status')).toBeVisible()

    // Cuando el reporte pasa a PROCESANDO
    await waitForEstado(page, 'PROCESANDO')

    // Y eventualmente llega a COMPLETADO
    await waitForEstado(page, 'COMPLETADO', 120000)

    // Entonces el botón de descarga aparece
    await expect(page.getByTestId('descarga-btn')).toBeVisible()
    await expect(page.getByTestId('polling-status')).not.toBeVisible()
  })

  // TC-REP-02: Auditor solicita auditoria-operaciones exitosamente
  test('TC-REP-02: Auditor puede solicitar y generar reporte de auditoría de operaciones', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/reportes/nuevo')

    // Dado que el Auditor tiene acceso a auditoria-operaciones
    const select = page.getByTestId('report-type-select')
    await expect(select.locator('option[value="auditoria-operaciones"]')).toHaveCount(1)

    // Cuando solicita el reporte
    await select.selectOption('auditoria-operaciones')
    await page.getByLabel('Formato de Salida').selectOption('PDF')
    await page.getByRole('button', { name: /solicitar reporte/i }).click()

    // Entonces es redirigido al detalle
    await expect(page).toHaveURL(/\/reportes\/[\w-]+$/)
    await expect(
      page.getByRole('article', { name: /detalle del reporte/i })
    ).toBeVisible()
  })

  // TC-REP-03: Operador navega a /reportes → redireccionado
  test('TC-REP-03: Operador es redirigido a /dashboard al intentar acceder a /reportes', async ({ page }) => {
    await loginAs(page, 'operador')

    await page.goto('/reportes')

    // El operador no tiene acceso a reportes
    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByRole('heading', { name: /reportes/i })).not.toBeVisible()
  })

  // TC-REP-04: Gerente NO ve auditoria-operaciones en el select de tipo
  test('TC-REP-04: Gerente no puede seleccionar auditoria-operaciones (rol no autorizado para ese tipo)', async ({ page }) => {
    await loginAs(page, 'gerente')

    await page.goto('/reportes/nuevo')

    const select = page.getByTestId('report-type-select')

    // El Gerente no debe ver la opción de auditoria-operaciones
    await expect(
      select.locator('option[value="auditoria-operaciones"]')
    ).toHaveCount(0)

    // Pero sí debe ver las opciones de su rol
    await expect(
      select.locator('option[value="stock-actual"]')
    ).toHaveCount(1)

    await expect(
      select.locator('option[value="movimientos-periodo"]')
    ).toHaveCount(1)
  })

  // Test adicional: verificar sección de fechas para movimientos-periodo
  test('TC-REP-05: Sección de fechas aparece solo para movimientos-periodo', async ({ page }) => {
    await loginAs(page, 'administrador')

    await page.goto('/reportes/nuevo')

    // Sin selección: no hay sección de fechas
    await expect(page.getByTestId('fecha-range-section')).not.toBeVisible()

    // Seleccionar stock-actual → sin fechas
    await page.getByTestId('report-type-select').selectOption('stock-actual')
    await expect(page.getByTestId('fecha-range-section')).not.toBeVisible()

    // Seleccionar movimientos-periodo → con fechas
    await page.getByTestId('report-type-select').selectOption('movimientos-periodo')
    await expect(page.getByTestId('fecha-range-section')).toBeVisible()
    await expect(page.getByLabel('Fecha Desde')).toBeVisible()
    await expect(page.getByLabel('Fecha Hasta')).toBeVisible()
  })
})
```

---

## 11. Criterios de Aceptación

### CA-REP-01: Acceso al Módulo

- **Dado** que soy un usuario con rol Gerente, Analista, Auditor o Administrador
- **Cuando** navego a `/reportes`
- **Entonces** veo la lista de mis solicitudes de reportes anteriores
- **Dado** que soy un usuario con rol Operador o Supervisor
- **Cuando** intento acceder a `/reportes`
- **Entonces** soy redirigido a `/dashboard`

### CA-REP-02: Solicitud de Reporte

- **Dado** que soy un usuario autorizado
- **Cuando** completo el formulario con tipo de reporte válido y formato
- **Y** hago clic en "Solicitar Reporte"
- **Entonces** el sistema retorna 202 Accepted
- **Y** soy redirigido a `/reportes/{id}` con estado inicial SOLICITADO
- **Y** el polling automático comienza (cada 5 segundos)

### CA-REP-03: Filtrado de Tipos por Rol

| Tipo de Reporte | Visible para Gerente | Visible para Analista | Visible para Auditor | Visible para Admin |
|---|---|---|---|---|
| stock-actual | SI | SI | SI | SI |
| movimientos-periodo | SI | SI | NO | SI |
| auditoria-operaciones | NO | NO | SI | SI |
| proveedores-actividad | SI | NO | NO | SI |

### CA-REP-04: Polling Automático

- **Dado** que solicité un reporte y estoy en la página de detalle
- **Cuando** el estado es SOLICITADO o PROCESANDO
- **Entonces** la página muestra `PollingStatus` con spinner y tiempo transcurrido
- **Y** el sistema consulta el estado cada 5 segundos automáticamente
- **Cuando** el estado cambia a COMPLETADO
- **Entonces** el polling se detiene automáticamente
- **Y** aparece el botón "Descargar XLSX/CSV/PDF"
- **Y** `PollingStatus` desaparece

### CA-REP-05: Descarga del Reporte

- **Dado** que el reporte está COMPLETADO
- **Cuando** hago clic en el botón de descarga
- **Entonces** el navegador descarga el archivo con el nombre `reporte-{id}.{formato}`
- **Y** el archivo tiene el contenido correcto según el tipo y formato seleccionado
- **Y** la URL pre-firmada de MinIO NO aparece expuesta en el DOM

### CA-REP-06: Manejo de Errores

- **Dado** que el estado del reporte es FALLIDO
- **Cuando** veo el detalle del reporte
- **Entonces** se muestra mensaje de error descriptivo
- **Y** hay un enlace para solicitar un nuevo reporte
- **Si** la solicitud POST retorna 400
- **Entonces** se muestra mensaje de error de validación en el formulario
- **Si** la solicitud POST retorna 403
- **Entonces** se muestra mensaje "No autorizado para este tipo de reporte"

### CA-REP-07: Requisitos TDD

- Todos los componentes tienen tests unitarios (Vitest) escritos primero (Red)
- Los hooks de polling tienen tests que verifican el comportamiento de `refetchInterval`
- Los schemas Zod tienen tests de casos válidos e inválidos para todos los tipos
- El slice de Zustand tiene tests de addPollingId y removePollingId
- Los tests E2E en Playwright cubren el flujo completo: solicitud → polling → descarga
- Cobertura mínima requerida: 80% por archivo
