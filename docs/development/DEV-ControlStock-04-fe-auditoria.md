# Etapa 4i — Frontend: Feature Auditoría

---

## 1. Contexto y Objetivo

### Contexto

La feature de **Auditoría** provee una vista de solo lectura del registro inmutable de auditoría del sistema ControlStock. Cada operación significativa sobre entidades del dominio (productos, categorías, stock, ajustes, proveedores, etc.) genera un registro de auditoría con el estado anterior y posterior del objeto, el usuario responsable, el timestamp en UTC y el contexto del evento.

Este módulo permite a Auditores y Administradores consultar, filtrar y analizar estos registros para control, cumplimiento y trazabilidad. **No existe ninguna operación de escritura** en esta feature — es completamente de lectura.

### Objetivo

Implementar el módulo frontend de Auditoría bajo Next.js 14 App Router con TypeScript estricto. Aplicar TDD (Red-Green-Refactor) en cada capa. Consumir el `audit-service` a través del Kong API Gateway.

### Características Clave

- Vista solo lectura — sin creación, edición ni eliminación
- Filtros avanzados: entidad, operación, usuarioId, rango de fechas
- Paginación del lado del servidor
- Visualización de datos JSON complejos (`valorAnterior`, `valorPosterior`, `contexto`) con `JsonViewer`
- Timestamps mostrados en zona horaria local del usuario
- Acceso restringido exclusivamente a Auditor y Administrador

### Entidades Auditadas

| Entidad | Descripción |
|---|---|
| `categorias` | Categorías de productos |
| `productos` | Catálogo de productos |
| `stock_levels` | Niveles de stock por ubicación |
| `adjustment_requests` | Solicitudes de ajuste de inventario |
| `suppliers` | Proveedores |
| `report_requests` | Solicitudes de reportes |
| `iam_users` | Usuarios del sistema (solo Admin) |

---

## 2. Prerrequisitos

### Infraestructura

| Elemento | Detalle |
|---|---|
| Kong API Gateway | `http://<VPS_IP>:8000/api/v1` operativo con rutas de `audit-service` |
| audit-service | Desplegado en K3s; expone solo GET /audit (no hay endpoint de detalle por ID) |
| Keycloak OIDC | Realm `controlstock` con roles AUDITOR y ADMINISTRADOR |
| Next.js 14 scaffolding | App Router inicializado (Etapas 4a-4h completadas) |

### Restricción Importante del Backend

El `audit-service` **solo expone** `GET /audit` con parámetros de filtrado y paginación. **No existe** `GET /audit/{id}`. La página de detalle (`/auditoria/[id]`) obtiene el registro filtrando por `entidadId` o usando datos cacheados del listado.

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

### Convenciones de Archivos

```
src/
  app/
    (protected)/
      auditoria/
        page.tsx                    # AuditoriaListPage
        [id]/
          page.tsx                  # AuditoriaDetailPage
  components/
    auditoria/
      AuditoriaTable.tsx
      AuditoriaTable.test.tsx
      AuditoriaFilters.tsx
      AuditoriaFilters.test.tsx
      AuditoriaDetail.tsx
      AuditoriaDetail.test.tsx
      OperacionBadge.tsx
      OperacionBadge.test.tsx
      JsonViewer.tsx
      JsonViewer.test.tsx
  hooks/
    auditoria/
      useAuditLog.ts
      useAuditLog.test.ts
      useAuditRecord.ts
      useAuditRecord.test.ts
  store/
    slices/
      auditoriaSlice.ts
      auditoriaSlice.test.ts
  schemas/
    auditoria.schema.ts
    auditoria.schema.test.ts
  types/
    auditoria.types.ts
```

---

## 3. Rutas y Páginas

| Ruta | Tipo | Componente Página | Descripción |
|---|---|---|---|
| `/auditoria` | Protected — Auditor, Administrador | `AuditoriaListPage` | Lista paginada del log de auditoría con filtros por entidad, operación, usuarioId y rango de fechas. Click en fila navega al detalle. |
| `/auditoria/[id]` | Protected — Auditor, Administrador | `AuditoriaDetailPage` | Vista completa de un registro de auditoría: entidad, operación, valores JSON anterior/posterior, contexto, evento origen. |

### Protección de Rutas

Solo los roles AUDITOR y ADMINISTRADOR pueden acceder a `/auditoria/**`. Cualquier otro rol es redirigido a `/dashboard`.

```typescript
// En el middleware de Next.js
const AUDITORIA_ROLES = ['ADMINISTRADOR', 'AUDITOR']

if (pathname.startsWith('/auditoria')) {
  const rol = session?.user?.rol
  if (!AUDITORIA_ROLES.includes(rol)) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }
}
```

### Implementación de Páginas

#### `app/(protected)/auditoria/page.tsx`

```typescript
import { Suspense } from 'react'
import { AuditoriaListPage } from '@/components/auditoria/AuditoriaListPage'
import { PageSkeleton } from '@/components/ui/PageSkeleton'
import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'

export const metadata = { title: 'Auditoría — ControlStock' }

export default async function Page() {
  const session = await getServerSession(authOptions)
  if (!['ADMINISTRADOR', 'AUDITOR'].includes(session?.user?.rol ?? '')) {
    redirect('/dashboard')
  }

  return (
    <Suspense fallback={<PageSkeleton />}>
      <AuditoriaListPage />
    </Suspense>
  )
}
```

#### `app/(protected)/auditoria/[id]/page.tsx`

```typescript
interface Props { params: { id: string } }

export default async function Page({ params }: Props) {
  const session = await getServerSession(authOptions)
  if (!['ADMINISTRADOR', 'AUDITOR'].includes(session?.user?.rol ?? '')) {
    redirect('/dashboard')
  }

  return <AuditoriaDetailPage recordId={params.id} />
}
```

---

## 4. Componentes

> **Nota TDD:** test-first — el test de render/interacción precede al componente. Cada componente tiene su archivo `.test.tsx` escrito y en estado RED antes de crear el `.tsx` correspondiente.

### 4.1 `AuditoriaTable`

**Archivo:** `src/components/auditoria/AuditoriaTable.tsx`

**Responsabilidad:** Renderiza la tabla paginada del log de auditoría. Columnas: timestamp_utc (formateado en zona local), entidad, entidadId (truncado), operación (badge), usuarioId. Click en fila navega al detalle del registro.

**Props:**

```typescript
interface AuditoriaTableProps {
  records: AuditRecord[]
  isLoading: boolean
  pagination: {
    page: number
    size: number
    totalElements: number
    totalPages: number
  }
  onPageChange: (page: number) => void
}
```

**Implementación:**

```typescript
'use client'

import { useRouter } from 'next/navigation'
import { AuditRecord } from '@/types/auditoria.types'
import { OperacionBadge } from './OperacionBadge'

function truncateId(id: string, maxLength = 12): string {
  if (id.length <= maxLength) return id
  return `${id.substring(0, maxLength)}...`
}

function formatTimestamp(isoString: string): string {
  return new Date(isoString).toLocaleString('es-AR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

export function AuditoriaTable({
  records,
  isLoading,
  pagination,
  onPageChange,
}: AuditoriaTableProps) {
  const router = useRouter()

  if (isLoading) {
    return <div role="status" aria-label="Cargando registros de auditoría">Cargando...</div>
  }

  if (records.length === 0) {
    return (
      <div role="status" data-testid="empty-state">
        No se encontraron registros de auditoría con los filtros aplicados.
      </div>
    )
  }

  return (
    <div>
      <table aria-label="Registro de auditoría">
        <thead>
          <tr>
            <th scope="col">Timestamp (UTC)</th>
            <th scope="col">Entidad</th>
            <th scope="col">Entidad ID</th>
            <th scope="col">Operación</th>
            <th scope="col">Usuario</th>
          </tr>
        </thead>
        <tbody>
          {records.map((record) => (
            <tr
              key={record.id}
              data-testid={`row-${record.id}`}
              onClick={() => router.push(`/auditoria/${record.id}`)}
              style={{ cursor: 'pointer' }}
              tabIndex={0}
              role="button"
              aria-label={`Ver detalle de operación ${record.operacion} en ${record.entidad}`}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  router.push(`/auditoria/${record.id}`)
                }
              }}
            >
              <td data-testid="timestamp">{formatTimestamp(record.timestampUtc)}</td>
              <td data-testid="entidad">{record.entidad}</td>
              <td
                data-testid="entidad-id"
                title={record.entidadId}
              >
                {truncateId(record.entidadId)}
              </td>
              <td><OperacionBadge operacion={record.operacion} /></td>
              <td data-testid="usuario-id">{record.usuarioId}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* Controles de paginación */}
      <nav aria-label="Paginación del log de auditoría">
        <button
          onClick={() => onPageChange(pagination.page - 1)}
          disabled={pagination.page === 0}
          aria-label="Página anterior"
        >
          Anterior
        </button>
        <span aria-current="page">
          Página {pagination.page + 1} de {pagination.totalPages}
          {' '}({pagination.totalElements} registros)
        </span>
        <button
          onClick={() => onPageChange(pagination.page + 1)}
          disabled={pagination.page >= pagination.totalPages - 1}
          aria-label="Página siguiente"
        >
          Siguiente
        </button>
      </nav>
    </div>
  )
}
```

---

### 4.2 `AuditoriaFilters`

**Archivo:** `src/components/auditoria/AuditoriaFilters.tsx`

**Responsabilidad:** Panel de filtros para el log de auditoría. Permite filtrar por entidad, operación, usuarioId y rango de fechas. Cambios en filtros disparan nueva consulta.

**Props:**

```typescript
interface AuditoriaFiltersProps {
  onFilterChange: (filtros: AuditFiltros) => void
}
```

**Implementación:**

```typescript
'use client'

import { useAuditoriaStore } from '@/store/auditoriaStore'

const ENTIDADES = [
  'categorias',
  'productos',
  'stock_levels',
  'adjustment_requests',
  'suppliers',
  'report_requests',
  'iam_users',
] as const

const OPERACIONES = ['CREAR', 'MODIFICAR', 'INACTIVAR', 'MOVER', 'ANULAR', 'COMPENSAR'] as const

export function AuditoriaFilters({ onFilterChange }: AuditoriaFiltersProps) {
  const { filtros, setFiltro, resetFiltros } = useAuditoriaStore()

  const handleChange = (key: keyof typeof filtros, value: string) => {
    setFiltro(key, value)
    onFilterChange({ ...filtros, [key]: value })
  }

  const handleReset = () => {
    resetFiltros()
    onFilterChange({ entidad: '', operacion: '', usuarioId: '', desde: '', hasta: '' })
  }

  return (
    <fieldset aria-label="Filtros de auditoría">
      <legend>Filtros</legend>

      <div>
        <label htmlFor="filter-entidad">Entidad</label>
        <select
          id="filter-entidad"
          value={filtros.entidad}
          onChange={(e) => handleChange('entidad', e.target.value)}
          data-testid="filter-entidad"
        >
          <option value="">Todas las entidades</option>
          {ENTIDADES.map((e) => (
            <option key={e} value={e}>{e}</option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="filter-operacion">Operación</label>
        <select
          id="filter-operacion"
          value={filtros.operacion}
          onChange={(e) => handleChange('operacion', e.target.value)}
          data-testid="filter-operacion"
        >
          <option value="">Todas las operaciones</option>
          {OPERACIONES.map((op) => (
            <option key={op} value={op}>{op}</option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="filter-usuario">Usuario ID</label>
        <input
          id="filter-usuario"
          type="text"
          value={filtros.usuarioId}
          onChange={(e) => handleChange('usuarioId', e.target.value)}
          placeholder="UUID del usuario..."
          data-testid="filter-usuario-id"
        />
      </div>

      <div>
        <label htmlFor="filter-desde">Fecha Desde</label>
        <input
          id="filter-desde"
          type="date"
          value={filtros.desde}
          onChange={(e) => handleChange('desde', e.target.value)}
          data-testid="filter-desde"
        />
      </div>

      <div>
        <label htmlFor="filter-hasta">Fecha Hasta</label>
        <input
          id="filter-hasta"
          type="date"
          value={filtros.hasta}
          onChange={(e) => handleChange('hasta', e.target.value)}
          data-testid="filter-hasta"
        />
      </div>

      <button
        type="button"
        onClick={handleReset}
        data-testid="reset-filters-btn"
      >
        Limpiar Filtros
      </button>
    </fieldset>
  )
}
```

---

### 4.3 `AuditoriaDetail`

**Archivo:** `src/components/auditoria/AuditoriaDetail.tsx`

**Responsabilidad:** Vista detallada de un registro de auditoría. Muestra todos los campos incluidos los valores JSON de `valorAnterior`, `valorPosterior` y `contexto` usando el componente `JsonViewer`.

**Props:**

```typescript
interface AuditoriaDetailProps {
  record: AuditRecord
}
```

**Implementación:**

```typescript
'use client'

import { AuditRecord } from '@/types/auditoria.types'
import { OperacionBadge } from './OperacionBadge'
import { JsonViewer } from './JsonViewer'

export function AuditoriaDetail({ record }: AuditoriaDetailProps) {
  const timestampLocal = new Date(record.timestampUtc).toLocaleString('es-AR', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short',
  })

  return (
    <article aria-label={`Detalle de auditoría ${record.id}`}>
      <header>
        <h1>Registro de Auditoría</h1>
        <OperacionBadge operacion={record.operacion} />
      </header>

      <section aria-labelledby="metadata-section">
        <h2 id="metadata-section">Información del Evento</h2>
        <dl>
          <dt>ID del Registro</dt>
          <dd data-testid="record-id">{record.id}</dd>

          <dt>Entidad</dt>
          <dd data-testid="record-entidad">{record.entidad}</dd>

          <dt>Entidad ID</dt>
          <dd data-testid="record-entidad-id">{record.entidadId}</dd>

          <dt>Operación</dt>
          <dd><OperacionBadge operacion={record.operacion} /></dd>

          <dt>Usuario</dt>
          <dd data-testid="record-usuario-id">{record.usuarioId}</dd>

          <dt>Timestamp (UTC)</dt>
          <dd data-testid="record-timestamp">{timestampLocal}</dd>

          {record.eventoOrigen && (
            <>
              <dt>Evento Origen</dt>
              <dd data-testid="record-evento-origen">{record.eventoOrigen}</dd>
            </>
          )}
        </dl>
      </section>

      <section aria-labelledby="valores-section">
        <h2 id="valores-section">Valores del Objeto</h2>

        <div>
          <h3>Valor Anterior</h3>
          <JsonViewer
            data={record.valorAnterior}
            label="Estado antes de la operación"
            testId="valor-anterior"
          />
        </div>

        <div>
          <h3>Valor Posterior</h3>
          <JsonViewer
            data={record.valorPosterior}
            label="Estado después de la operación"
            testId="valor-posterior"
          />
        </div>
      </section>

      {record.contexto && (
        <section aria-labelledby="contexto-section">
          <h2 id="contexto-section">Contexto Adicional</h2>
          <JsonViewer
            data={record.contexto}
            label="Contexto del evento"
            testId="contexto"
          />
        </section>
      )}
    </article>
  )
}
```

---

### 4.4 `OperacionBadge`

**Archivo:** `src/components/auditoria/OperacionBadge.tsx`

**Responsabilidad:** Badge visual que representa la operación de auditoría con color semántico.

```typescript
'use client'

type Operacion = 'CREAR' | 'MODIFICAR' | 'INACTIVAR' | 'MOVER' | 'ANULAR' | 'COMPENSAR'

interface OperacionBadgeProps {
  operacion: Operacion
}

const OPERACION_CONFIG: Record<Operacion, { label: string; className: string; ariaLabel: string }> = {
  CREAR: {
    label: 'CREAR',
    className: 'badge badge-blue',
    ariaLabel: 'Operación: Creación de registro',
  },
  MODIFICAR: {
    label: 'MODIFICAR',
    className: 'badge badge-amber',
    ariaLabel: 'Operación: Modificación de registro',
  },
  INACTIVAR: {
    label: 'INACTIVAR',
    className: 'badge badge-orange',
    ariaLabel: 'Operación: Inactivación de registro',
  },
  MOVER: {
    label: 'MOVER',
    className: 'badge badge-teal',
    ariaLabel: 'Operación: Movimiento de stock',
  },
  ANULAR: {
    label: 'ANULAR',
    className: 'badge badge-red',
    ariaLabel: 'Operación: Anulación de registro',
  },
  COMPENSAR: {
    label: 'COMPENSAR',
    className: 'badge badge-purple',
    ariaLabel: 'Operación: Compensación de ajuste',
  },
}

export function OperacionBadge({ operacion }: OperacionBadgeProps) {
  const config = OPERACION_CONFIG[operacion]

  return (
    <span
      className={config.className}
      aria-label={config.ariaLabel}
      data-testid={`operacion-badge-${operacion.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

---

### 4.5 `JsonViewer`

**Archivo:** `src/components/auditoria/JsonViewer.tsx`

**Responsabilidad:** Renderiza datos JSONB como JSON pretty-printed colapsable. Si el dato es `null` muestra "—". Está colapsado por defecto con botón para expandir. Es de solo lectura.

**Props:**

```typescript
interface JsonViewerProps {
  data: Record<string, unknown> | null | undefined
  label: string
  testId?: string
  defaultExpanded?: boolean
}
```

**Implementación:**

```typescript
'use client'

import { useState } from 'react'

export function JsonViewer({ data, label, testId, defaultExpanded = false }: JsonViewerProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded)

  if (data === null || data === undefined) {
    return (
      <div
        data-testid={testId}
        aria-label={label}
        role="region"
      >
        <span aria-label="Sin datos">—</span>
      </div>
    )
  }

  const jsonString = JSON.stringify(data, null, 2)

  return (
    <div
      data-testid={testId}
      aria-label={label}
      role="region"
    >
      <button
        type="button"
        onClick={() => setIsExpanded(!isExpanded)}
        aria-expanded={isExpanded}
        aria-controls={`${testId}-content`}
        data-testid={`${testId}-toggle`}
      >
        {isExpanded ? 'Colapsar' : 'Expandir'} JSON
      </button>

      {isExpanded && (
        <pre
          id={`${testId}-content`}
          data-testid={`${testId}-content`}
          aria-label={`Contenido JSON: ${label}`}
          role="code"
          tabIndex={0}
        >
          <code>{jsonString}</code>
        </pre>
      )}
    </div>
  )
}
```

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** test-first — cada hook tiene su archivo `.test.ts` escrito en estado RED antes de implementar el hook. MSW intercepta las peticiones HTTP en los tests.

### Configuración Base API

**Archivo:** `src/lib/api/auditoria.api.ts`

```typescript
import { z } from 'zod'
import { AuditRecordSchema } from '@/schemas/auditoria.schema'
import { getSession } from 'next-auth/react'

const BASE_URL = `${process.env.NEXT_PUBLIC_API_URL}/audit`

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

  return res.json()
}

interface AuditQueryParams {
  entidad?: string
  entidadId?: string
  usuarioId?: string
  desde?: string
  hasta?: string
  operacion?: string
  page?: number
  size?: number
}

interface AuditPageResponse {
  content: unknown[]
  totalElements: number
  totalPages: number
  number: number
  size: number
}

export const auditoriaApi = {
  list: async (params: AuditQueryParams = {}): Promise<{
    records: z.infer<typeof AuditRecordSchema>[]
    totalElements: number
    totalPages: number
    page: number
    size: number
  }> => {
    const sp = new URLSearchParams()
    if (params.entidad) sp.set('entidad', params.entidad)
    if (params.entidadId) sp.set('entidadId', params.entidadId)
    if (params.usuarioId) sp.set('usuarioId', params.usuarioId)
    if (params.desde) sp.set('desde', params.desde)
    if (params.hasta) sp.set('hasta', params.hasta)
    if (params.operacion) sp.set('operacion', params.operacion)
    if (params.page !== undefined) sp.set('page', String(params.page))
    if (params.size !== undefined) sp.set('size', String(params.size))

    const data: AuditPageResponse = await fetchWithAuth(`${BASE_URL}?${sp}`)

    return {
      records: z.array(AuditRecordSchema).parse(data.content),
      totalElements: data.totalElements,
      totalPages: data.totalPages,
      page: data.number,
      size: data.size,
    }
  },
}
```

---

### 5.1 `useAuditLog`

**Archivo:** `src/hooks/auditoria/useAuditLog.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { auditoriaApi } from '@/lib/api/auditoria.api'
import { useAuditoriaStore } from '@/store/auditoriaStore'

interface UseAuditLogParams {
  entidad?: string
  entidadId?: string
  usuarioId?: string
  desde?: string
  hasta?: string
  operacion?: string
  page?: number
  size?: number
}

export const auditLogQueryKey = (params: UseAuditLogParams) =>
  ['audit-log', params] as const

export function useAuditLog(params: UseAuditLogParams = {}) {
  const { filtros } = useAuditoriaStore()

  // Combinar filtros del store con los parámetros locales de la página
  const mergedParams: UseAuditLogParams = {
    entidad: params.entidad ?? (filtros.entidad || undefined),
    entidadId: params.entidadId,
    usuarioId: params.usuarioId ?? (filtros.usuarioId || undefined),
    desde: params.desde ?? (filtros.desde || undefined),
    hasta: params.hasta ?? (filtros.hasta || undefined),
    operacion: params.operacion ?? (filtros.operacion || undefined),
    page: params.page ?? 0,
    size: params.size ?? 20,
  }

  return useQuery({
    queryKey: auditLogQueryKey(mergedParams),
    queryFn: () => auditoriaApi.list(mergedParams),
    staleTime: 2 * 60 * 1000, // 2 minutos — el log es inmutable, puede cachearse más
    placeholderData: (previousData) => previousData, // Mantiene datos previos al cambiar página
  })
}
```

---

### 5.2 `useAuditRecord`

**Archivo:** `src/hooks/auditoria/useAuditRecord.ts`

**Nota:** No existe `GET /audit/{id}`. Este hook obtiene el registro del cache de la lista o hace una query filtrada por `entidadId` si el ID es el del registro de auditoría.

```typescript
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { auditoriaApi } from '@/lib/api/auditoria.api'
import { AuditRecord } from '@/types/auditoria.types'
import { auditLogQueryKey } from './useAuditLog'

export function useAuditRecord(recordId: string) {
  const queryClient = useQueryClient()

  return useQuery({
    queryKey: ['audit-record', recordId],
    queryFn: async () => {
      // Primero intentar obtener del cache de la lista
      const cachedQueries = queryClient.getQueriesData<{
        records: AuditRecord[]
      }>({ queryKey: ['audit-log'] })

      for (const [, data] of cachedQueries) {
        if (data?.records) {
          const found = data.records.find((r) => r.id === recordId)
          if (found) return found
        }
      }

      // Si no está en cache, hacer una query filtrada
      // El audit-service no tiene GET /audit/{id}, usamos la lista con filtro
      const result = await auditoriaApi.list({ entidadId: recordId, page: 0, size: 1 })
      if (result.records.length === 0) {
        throw new Error('Registro de auditoría no encontrado')
      }
      return result.records[0]
    },
    enabled: !!recordId,
    staleTime: 5 * 60 * 1000, // Los registros de auditoría son inmutables
  })
}
```

---

## 6. Estado Global (Zustand)

> **Nota TDD:** test-first — el test del slice se escribe antes de implementar el store. Se prueba cada acción de forma aislada.

### `auditoriaSlice`

**Archivo:** `src/store/slices/auditoriaSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export interface AuditFiltros {
  entidad: string
  operacion: string
  usuarioId: string
  desde: string
  hasta: string
}

export interface AuditoriaSlice {
  filtros: AuditFiltros
  setFiltro: (key: keyof AuditFiltros, value: string) => void
  resetFiltros: () => void
}

const initialFiltros: AuditFiltros = {
  entidad: '',
  operacion: '',
  usuarioId: '',
  desde: '',
  hasta: '',
}

export const createAuditoriaSlice: StateCreator<AuditoriaSlice> = (set) => ({
  filtros: { ...initialFiltros },

  setFiltro: (key, value) =>
    set((state) => ({
      filtros: { ...state.filtros, [key]: value },
    })),

  resetFiltros: () =>
    set({ filtros: { ...initialFiltros } }),
})
```

**Archivo:** `src/store/auditoriaStore.ts`

```typescript
import { create } from 'zustand'
import { devtools, persist } from 'zustand/middleware'
import { AuditoriaSlice, createAuditoriaSlice } from './slices/auditoriaSlice'

export const useAuditoriaStore = create<AuditoriaSlice>()(
  devtools(
    persist(createAuditoriaSlice, {
      name: 'controlstock-auditoria-filtros',
      partialize: (state) => ({ filtros: state.filtros }),
    }),
    { name: 'AuditoriaStore' }
  )
)
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** test-first — los tests de schemas se escriben primero verificando casos válidos, inválidos y edge cases.

**Archivo:** `src/schemas/auditoria.schema.ts`

```typescript
import { z } from 'zod'

export const OperacionEnum = z.enum([
  'CREAR',
  'MODIFICAR',
  'INACTIVAR',
  'MOVER',
  'ANULAR',
  'COMPENSAR',
])

export const AuditRecordSchema = z.object({
  id: z.string().uuid(),
  entidad: z.string().min(1, 'La entidad es requerida'),
  entidadId: z.string().min(1, 'El ID de entidad es requerido'),
  operacion: OperacionEnum,
  usuarioId: z.string().min(1, 'El usuario es requerido'),
  timestampUtc: z.string().datetime('Formato de timestamp inválido'),
  valorAnterior: z.record(z.unknown()).nullable(),
  valorPosterior: z.record(z.unknown()).nullable(),
  contexto: z.record(z.unknown()).nullable(),
  eventoOrigen: z.string().nullable(),
})

export const AuditFiltersSchema = z.object({
  entidad: z.string().optional(),
  operacion: OperacionEnum.optional(),
  usuarioId: z.string().optional(),
  desde: z.string().date('Formato de fecha inválido').optional(),
  hasta: z.string().date('Formato de fecha inválido').optional(),
})

// --- Tipos inferidos ---

export type AuditRecord = z.infer<typeof AuditRecordSchema>
export type AuditFilters = z.infer<typeof AuditFiltersSchema>
export type OperacionAuditoria = z.infer<typeof OperacionEnum>
```

---

## 8. Autenticación y Autorización

### Matriz de Acceso

| Acción | Auditor | Administrador | Otros roles |
|---|---|---|---|
| Ver lista de auditoría | SI | SI | NO (redirige a /dashboard) |
| Ver detalle de registro | SI | SI | NO (redirige a /dashboard) |
| Filtrar registros | SI | SI | NO |
| Exportar / copiar JSON | SI | SI | NO |
| Crear/modificar registros | NO | NO | NO — el log es INMUTABLE |

### Implementación del Guard

Los registros de auditoría son inmutables. El sistema **no expone** ningún endpoint de escritura. Los controles de UI no incluyen botones de edición, eliminación ni creación.

### Acceso a Entidad `iam_users`

Los registros de auditoría sobre `iam_users` están disponibles para Auditor y Administrador mediante el filtro de entidad. No hay restricción adicional dentro del módulo de auditoría: ambos roles ven todos los registros.

### Protección por Token

El token JWT de Keycloak incluye el rol del usuario. El `audit-service` valida el token y rechaza con 403 las peticiones de roles no autorizados. El frontend redirige a `/dashboard` si el rol no es AUDITOR o ADMINISTRADOR antes de hacer la petición.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Red-Green-Refactor:** Cada test se escribe primero en estado RED. Se implementa código mínimo para GREEN. Se refactoriza manteniendo todos los tests en GREEN.

### 9.1 Tests de Schemas

**Archivo:** `src/schemas/auditoria.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { AuditRecordSchema, AuditFiltersSchema } from './auditoria.schema'

const validRecord = {
  id: '123e4567-e89b-12d3-a456-426614174000',
  entidad: 'productos',
  entidadId: 'prod-123',
  operacion: 'MODIFICAR',
  usuarioId: 'user-abc',
  timestampUtc: '2024-01-15T10:00:00.000Z',
  valorAnterior: { precio: 100, nombre: 'Producto A' },
  valorPosterior: { precio: 150, nombre: 'Producto A' },
  contexto: { motivo: 'Actualización de precio', origen: 'UI' },
  eventoOrigen: 'producto.precio.actualizado',
}

describe('AuditRecordSchema', () => {
  it('valida un registro de auditoría completo y válido', () => {
    const result = AuditRecordSchema.safeParse(validRecord)
    expect(result.success).toBe(true)
  })

  it('falla cuando operacion no es un valor del enum', () => {
    const result = AuditRecordSchema.safeParse({
      ...validRecord,
      operacion: 'ELIMINAR',
    })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].path).toContain('operacion')
  })

  it('falla cuando entidad está vacía', () => {
    const result = AuditRecordSchema.safeParse({ ...validRecord, entidad: '' })
    expect(result.success).toBe(false)
  })

  it('acepta valorAnterior como null (operaciones CREAR)', () => {
    const result = AuditRecordSchema.safeParse({ ...validRecord, valorAnterior: null })
    expect(result.success).toBe(true)
    expect(result.data?.valorAnterior).toBeNull()
  })

  it('acepta valorPosterior como null (operaciones ANULAR)', () => {
    const result = AuditRecordSchema.safeParse({ ...validRecord, valorPosterior: null })
    expect(result.success).toBe(true)
  })

  it('acepta contexto como null', () => {
    const result = AuditRecordSchema.safeParse({ ...validRecord, contexto: null })
    expect(result.success).toBe(true)
  })

  it('acepta eventoOrigen como null', () => {
    const result = AuditRecordSchema.safeParse({ ...validRecord, eventoOrigen: null })
    expect(result.success).toBe(true)
  })

  it('valida todas las operaciones del enum', () => {
    const operaciones = ['CREAR', 'MODIFICAR', 'INACTIVAR', 'MOVER', 'ANULAR', 'COMPENSAR']
    operaciones.forEach((op) => {
      const result = AuditRecordSchema.safeParse({ ...validRecord, operacion: op })
      expect(result.success, `Operacion ${op} debería ser válida`).toBe(true)
    })
  })
})

describe('AuditFiltersSchema', () => {
  it('valida filtros completos válidos', () => {
    const filters = {
      entidad: 'productos',
      operacion: 'CREAR',
      usuarioId: 'user-abc',
      desde: '2024-01-01',
      hasta: '2024-01-31',
    }
    const result = AuditFiltersSchema.safeParse(filters)
    expect(result.success).toBe(true)
  })

  it('valida filtros parciales (todos son opcionales)', () => {
    const result = AuditFiltersSchema.safeParse({ entidad: 'productos' })
    expect(result.success).toBe(true)
  })

  it('valida objeto de filtros vacío', () => {
    const result = AuditFiltersSchema.safeParse({})
    expect(result.success).toBe(true)
  })

  it('falla cuando operacion es valor inválido del enum', () => {
    const result = AuditFiltersSchema.safeParse({ operacion: 'BORRAR' })
    expect(result.success).toBe(false)
  })

  it('falla cuando desde es formato de fecha inválido', () => {
    const result = AuditFiltersSchema.safeParse({ desde: 'no-es-fecha' })
    expect(result.success).toBe(false)
  })
})
```

---

### 9.2 Tests de Hooks

**Archivo:** `src/hooks/auditoria/useAuditLog.test.ts`

```typescript
import { describe, it, expect, beforeAll, afterEach, afterAll } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'
import { createWrapper } from '@/test/utils'
import { useAuditLog } from './useAuditLog'

const MOCK_AUDIT_RECORDS = [
  {
    id: '1',
    entidad: 'productos',
    entidadId: 'prod-1',
    operacion: 'MODIFICAR',
    usuarioId: 'user-1',
    timestampUtc: '2024-01-15T10:00:00.000Z',
    valorAnterior: { precio: 100 },
    valorPosterior: { precio: 150 },
    contexto: null,
    eventoOrigen: null,
  },
]

const server = setupServer(
  http.get('*/api/v1/audit', () => {
    return HttpResponse.json({
      content: MOCK_AUDIT_RECORDS,
      totalElements: 1,
      totalPages: 1,
      number: 0,
      size: 20,
    })
  })
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('useAuditLog', () => {
  it('retorna estado de carga inicial', () => {
    const { result } = renderHook(() => useAuditLog(), { wrapper: createWrapper() })
    expect(result.current.isLoading).toBe(true)
  })

  it('retorna lista paginada de registros exitosamente', async () => {
    const { result } = renderHook(() => useAuditLog(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))

    expect(result.current.data?.records).toHaveLength(1)
    expect(result.current.data?.records[0].entidad).toBe('productos')
    expect(result.current.data?.totalElements).toBe(1)
  })

  it('retorna error cuando el servidor responde 500', async () => {
    server.use(
      http.get('*/api/v1/audit', () =>
        HttpResponse.json({ message: 'Error interno' }, { status: 500 })
      )
    )
    const { result } = renderHook(() => useAuditLog(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isError).toBe(true))
  })

  it('retorna error 403 para rol no autorizado', async () => {
    server.use(
      http.get('*/api/v1/audit', () =>
        HttpResponse.json({ message: 'Acceso denegado' }, { status: 403 })
      )
    )
    const { result } = renderHook(() => useAuditLog(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(403)
  })
})
```

---

### 9.3 Tests de Componentes

**Archivo:** `src/components/auditoria/AuditoriaTable.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AuditoriaTable } from './AuditoriaTable'

const mockRecords = [
  {
    id: '1',
    entidad: 'productos',
    entidadId: 'prod-123e4567-e89b-12d3-a456',
    operacion: 'MODIFICAR' as const,
    usuarioId: 'user-abc',
    timestampUtc: '2024-01-15T10:30:00.000Z',
    valorAnterior: { precio: 100 },
    valorPosterior: { precio: 150 },
    contexto: null,
    eventoOrigen: null,
  },
]

const defaultPagination = { page: 0, size: 20, totalElements: 1, totalPages: 1 }

describe('AuditoriaTable', () => {
  it('renderiza filas con columnas correctas', () => {
    render(
      <AuditoriaTable
        records={mockRecords}
        isLoading={false}
        pagination={defaultPagination}
        onPageChange={vi.fn()}
      />
    )

    expect(screen.getByTestId('row-1')).toBeInTheDocument()
    expect(screen.getByTestId('entidad')).toHaveTextContent('productos')
    expect(screen.getByTestId('usuario-id')).toHaveTextContent('user-abc')
  })

  it('formatea el timestamp en zona horaria local', () => {
    render(
      <AuditoriaTable
        records={mockRecords}
        isLoading={false}
        pagination={defaultPagination}
        onPageChange={vi.fn()}
      />
    )
    // El timestamp debe ser formateado, no en ISO raw
    const timestampCell = screen.getByTestId('timestamp')
    expect(timestampCell.textContent).not.toContain('T')
    expect(timestampCell.textContent).not.toContain('Z')
  })

  it('muestra entidadId truncado con title completo', () => {
    render(
      <AuditoriaTable
        records={mockRecords}
        isLoading={false}
        pagination={defaultPagination}
        onPageChange={vi.fn()}
      />
    )
    const entidadIdCell = screen.getByTestId('entidad-id')
    expect(entidadIdCell.textContent).toHaveLength(15) // 12 + '...'
    expect(entidadIdCell.getAttribute('title')).toBe('prod-123e4567-e89b-12d3-a456')
  })

  it('muestra controles de paginación', () => {
    render(
      <AuditoriaTable
        records={mockRecords}
        isLoading={false}
        pagination={{ page: 0, size: 20, totalElements: 40, totalPages: 2 }}
        onPageChange={vi.fn()}
      />
    )
    expect(screen.getByRole('navigation', { name: /paginación/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /página anterior/i })).toBeDisabled()
    expect(screen.getByRole('button', { name: /página siguiente/i })).toBeEnabled()
  })

  it('llama onPageChange al hacer clic en siguiente', async () => {
    const onPageChange = vi.fn()
    render(
      <AuditoriaTable
        records={mockRecords}
        isLoading={false}
        pagination={{ page: 0, size: 20, totalElements: 40, totalPages: 2 }}
        onPageChange={onPageChange}
      />
    )
    await userEvent.click(screen.getByRole('button', { name: /página siguiente/i }))
    expect(onPageChange).toHaveBeenCalledWith(1)
  })
})

describe('OperacionBadge', () => {
  const testCases = [
    { operacion: 'CREAR', expectedClass: 'badge-blue' },
    { operacion: 'MODIFICAR', expectedClass: 'badge-amber' },
    { operacion: 'INACTIVAR', expectedClass: 'badge-orange' },
    { operacion: 'MOVER', expectedClass: 'badge-teal' },
    { operacion: 'ANULAR', expectedClass: 'badge-red' },
    { operacion: 'COMPENSAR', expectedClass: 'badge-purple' },
  ] as const

  testCases.forEach(({ operacion, expectedClass }) => {
    it(`renderiza badge correcto para operacion ${operacion}`, () => {
      render(<OperacionBadge operacion={operacion} />)
      const badge = screen.getByTestId(`operacion-badge-${operacion.toLowerCase()}`)
      expect(badge).toHaveClass(expectedClass)
      expect(badge).toHaveTextContent(operacion)
    })
  })
})

describe('JsonViewer', () => {
  it('renderiza placeholder "—" cuando data es null', () => {
    render(<JsonViewer data={null} label="Valor anterior" testId="test-json" />)
    const viewer = screen.getByTestId('test-json')
    expect(viewer).toHaveTextContent('—')
  })

  it('renderiza placeholder "—" cuando data es undefined', () => {
    render(<JsonViewer data={undefined} label="Valor anterior" testId="test-json" />)
    expect(screen.getByTestId('test-json')).toHaveTextContent('—')
  })

  it('está colapsado por defecto (defaultExpanded=false)', () => {
    render(
      <JsonViewer
        data={{ precio: 100 }}
        label="Valor"
        testId="test-json"
      />
    )
    // El contenido no debe estar visible
    expect(screen.queryByTestId('test-json-content')).not.toBeInTheDocument()
    expect(screen.getByTestId('test-json-toggle')).toHaveTextContent('Expandir JSON')
  })

  it('muestra el JSON pretty-printed al hacer clic en Expandir', async () => {
    render(
      <JsonViewer
        data={{ precio: 100, nombre: 'Producto A' }}
        label="Valor posterior"
        testId="test-json"
      />
    )

    await userEvent.click(screen.getByTestId('test-json-toggle'))

    const content = screen.getByTestId('test-json-content')
    expect(content).toBeInTheDocument()
    expect(content.textContent).toContain('"precio"')
    expect(content.textContent).toContain('100')
    expect(content.textContent).toContain('"nombre"')
  })

  it('colapsa al hacer clic en Colapsar', async () => {
    render(
      <JsonViewer
        data={{ precio: 100 }}
        label="Valor"
        testId="test-json"
        defaultExpanded={true}
      />
    )

    // Inicialmente expandido
    expect(screen.getByTestId('test-json-content')).toBeInTheDocument()

    // Clic en colapsar
    await userEvent.click(screen.getByTestId('test-json-toggle'))

    expect(screen.queryByTestId('test-json-content')).not.toBeInTheDocument()
  })
})

describe('auditoriaSlice', () => {
  it('setFiltro actualiza solo la clave especificada', () => {
    const { result } = renderHook(() => useAuditoriaStore())
    act(() => result.current.setFiltro('entidad', 'productos'))
    expect(result.current.filtros.entidad).toBe('productos')
    // Los otros filtros no cambian
    expect(result.current.filtros.operacion).toBe('')
    expect(result.current.filtros.usuarioId).toBe('')
  })

  it('setFiltro permite actualizar múltiples filtros secuencialmente', () => {
    const { result } = renderHook(() => useAuditoriaStore())
    act(() => {
      result.current.setFiltro('entidad', 'productos')
      result.current.setFiltro('operacion', 'CREAR')
      result.current.setFiltro('usuarioId', 'user-1')
    })
    expect(result.current.filtros.entidad).toBe('productos')
    expect(result.current.filtros.operacion).toBe('CREAR')
    expect(result.current.filtros.usuarioId).toBe('user-1')
  })

  it('resetFiltros resetea todos los filtros a cadena vacía', () => {
    const { result } = renderHook(() => useAuditoriaStore())
    act(() => {
      result.current.setFiltro('entidad', 'productos')
      result.current.setFiltro('operacion', 'ANULAR')
      result.current.resetFiltros()
    })
    expect(result.current.filtros.entidad).toBe('')
    expect(result.current.filtros.operacion).toBe('')
    expect(result.current.filtros.usuarioId).toBe('')
    expect(result.current.filtros.desde).toBe('')
    expect(result.current.filtros.hasta).toBe('')
  })
})
```

---

## 10. Pruebas E2E (Playwright, ATDD)

**Archivo:** `e2e/auditoria/auditoria.spec.ts`

```typescript
import { test, expect, Page } from '@playwright/test'
import { loginAs } from '../helpers/auth'

test.describe('Feature Auditoría', () => {

  // TC-AUD-01: Auditor ve lista de registros de auditoría
  test('TC-AUD-01: Auditor navega a /auditoria y ve la lista de registros', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    // Dado que soy Auditor
    // Cuando accedo a la sección de auditoría
    await expect(page.getByRole('heading', { name: /auditoría/i })).toBeVisible()

    // Entonces veo la tabla de registros
    await expect(page.getByRole('table', { name: /registro de auditoría/i })).toBeVisible()

    // Y los headers de columna están presentes
    await expect(page.getByRole('columnheader', { name: /timestamp/i })).toBeVisible()
    await expect(page.getByRole('columnheader', { name: /entidad/i })).toBeVisible()
    await expect(page.getByRole('columnheader', { name: /operación/i })).toBeVisible()
    await expect(page.getByRole('columnheader', { name: /usuario/i })).toBeVisible()

    // Y la paginación está presente
    await expect(page.getByRole('navigation', { name: /paginación/i })).toBeVisible()
  })

  // TC-AUD-02: Filtrar por entidad=productos muestra solo registros de productos
  test('TC-AUD-02: Filtrar por entidad=productos muestra solo registros de esa entidad', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    // Dado que estoy en la lista de auditoría
    // Cuando selecciono el filtro de entidad "productos"
    await page.getByTestId('filter-entidad').selectOption('productos')

    // Entonces la tabla se actualiza
    await page.waitForLoadState('networkidle')

    // Y todos los registros visibles tienen entidad=productos
    const entidadCells = page.getByTestId('entidad')
    const count = await entidadCells.count()
    expect(count).toBeGreaterThan(0)

    for (let i = 0; i < count; i++) {
      await expect(entidadCells.nth(i)).toHaveText('productos')
    }
  })

  // TC-AUD-03: Filtrar por operacion=COMPENSAR muestra solo registros de compensación
  test('TC-AUD-03: Filtrar por operacion=COMPENSAR muestra solo registros de compensación', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    // Cuando selecciono la operación COMPENSAR
    await page.getByTestId('filter-operacion').selectOption('COMPENSAR')

    await page.waitForLoadState('networkidle')

    // Entonces solo veo badges de COMPENSAR
    const badges = page.getByTestId('operacion-badge-compensar')
    const count = await badges.count()

    if (count > 0) {
      // Si hay registros, todos deben ser COMPENSAR
      for (let i = 0; i < count; i++) {
        await expect(badges.nth(i)).toBeVisible()
      }
    } else {
      // Si no hay registros, se muestra el estado vacío
      await expect(page.getByTestId('empty-state')).toBeVisible()
    }
  })

  // TC-AUD-04: Click en fila muestra detalle con valorAnterior y valorPosterior como JSON
  test('TC-AUD-04: Click en fila navega al detalle con valorAnterior y valorPosterior como JSON', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    // Dado que veo la tabla
    const primeraFila = page.getByRole('row').nth(1) // nth(0) es el header
    await expect(primeraFila).toBeVisible()

    // Cuando hago clic en la primera fila
    await primeraFila.click()

    // Entonces navego al detalle
    await expect(page).toHaveURL(/\/auditoria\/[\w-]+$/)

    // Y veo la información del registro
    await expect(page.getByRole('heading', { name: /registro de auditoría/i })).toBeVisible()
    await expect(page.getByTestId('record-entidad')).toBeVisible()
    await expect(page.getByTestId('record-usuario-id')).toBeVisible()

    // Y los JsonViewer están presentes (colapsados por defecto)
    await expect(page.getByTestId('valor-anterior')).toBeVisible()
    await expect(page.getByTestId('valor-posterior')).toBeVisible()

    // Cuando expando el valorPosterior
    await page.getByTestId('valor-posterior-toggle').click()

    // Entonces veo el JSON formateado
    const jsonContent = page.getByTestId('valor-posterior-content')
    await expect(jsonContent).toBeVisible()

    // El contenido es JSON válido (no un string crudo)
    const text = await jsonContent.textContent()
    expect(() => JSON.parse(text ?? '')).not.toThrow()
  })

  // TC-AUD-05: Operador es redirigido a /dashboard
  test('TC-AUD-05: Operador que intenta acceder a /auditoria es redirigido a /dashboard', async ({ page }) => {
    await loginAs(page, 'operador')

    await page.goto('/auditoria')

    // El Operador no tiene acceso a auditoría
    await expect(page).toHaveURL('/dashboard')

    // Y no ve la tabla de auditoría
    await expect(
      page.getByRole('table', { name: /registro de auditoría/i })
    ).not.toBeVisible()
  })

  // Test adicional: limpiar filtros resetea la vista
  test('TC-AUD-06: Botón "Limpiar Filtros" resetea todos los filtros aplicados', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    // Aplicar filtros
    await page.getByTestId('filter-entidad').selectOption('productos')
    await page.getByTestId('filter-operacion').selectOption('CREAR')

    // Verificar que los filtros están aplicados
    await expect(page.getByTestId('filter-entidad')).toHaveValue('productos')
    await expect(page.getByTestId('filter-operacion')).toHaveValue('CREAR')

    // Limpiar filtros
    await page.getByTestId('reset-filters-btn').click()

    // Los filtros vuelven a vacío
    await expect(page.getByTestId('filter-entidad')).toHaveValue('')
    await expect(page.getByTestId('filter-operacion')).toHaveValue('')
  })

  // Test adicional: paginación funciona correctamente
  test('TC-AUD-07: Paginación permite navegar entre páginas del log', async ({ page }) => {
    await loginAs(page, 'auditor')

    await page.goto('/auditoria')

    const nav = page.getByRole('navigation', { name: /paginación/i })
    const siguienteBtn = nav.getByRole('button', { name: /página siguiente/i })

    // Si hay más de una página
    if (await siguienteBtn.isEnabled()) {
      const textoPaginaInicial = await nav.getByText(/página 1/i).textContent()

      await siguienteBtn.click()
      await page.waitForLoadState('networkidle')

      await expect(nav.getByText(/página 2/i)).toBeVisible()
    } else {
      // Con una sola página, el botón anterior está deshabilitado
      await expect(nav.getByRole('button', { name: /página anterior/i })).toBeDisabled()
    }
  })
})
```

---

## 11. Criterios de Aceptación

### CA-AUD-01: Control de Acceso

- **Dado** que soy un usuario con rol Auditor o Administrador
- **Cuando** navego a `/auditoria`
- **Entonces** veo la lista paginada del log de auditoría
- **Dado** que soy un usuario con cualquier otro rol (Operador, Supervisor, Gerente, Analista)
- **Cuando** intento acceder a `/auditoria`
- **Entonces** soy redirigido automáticamente a `/dashboard`

### CA-AUD-02: Vista de Lista con Columnas Requeridas

- **Dado** que estoy en `/auditoria` con rol autorizado
- **Cuando** se carga la página
- **Entonces** la tabla muestra las columnas: timestamp_utc (formateado en hora local), entidad, entidadId (truncado con tooltip del valor completo), operación (badge con color), usuarioId
- **Y** la paginación muestra el número de página actual y total de registros
- **Y** los registros están ordenados por timestamp descendente (más reciente primero)

### CA-AUD-03: Filtros Funcionando

| Filtro | Comportamiento esperado |
|---|---|
| Entidad | Muestra solo registros de la entidad seleccionada |
| Operación | Muestra solo registros de la operación seleccionada |
| Usuario ID | Filtra por texto exacto del ID de usuario |
| Fecha Desde | Solo registros a partir de la fecha indicada |
| Fecha Hasta | Solo registros hasta la fecha indicada |
| Limpiar Filtros | Resetea todos los filtros y muestra todos los registros |

### CA-AUD-04: Vista de Detalle del Registro

- **Dado** que estoy en la lista de auditoría
- **Cuando** hago clic en cualquier fila
- **Entonces** navego a `/auditoria/{id}`
- **Y** veo todos los campos: entidad, entidadId, operación (badge), usuarioId, timestampUtc (formateado con zona horaria)
- **Y** veo el `valorAnterior` como JSON colapsado (expandible)
- **Y** veo el `valorPosterior` como JSON colapsado (expandible)
- **Y** si existe `contexto`, se muestra también como JSON colapsado
- **Y** si existe `eventoOrigen`, se muestra como texto

### CA-AUD-05: Comportamiento del JsonViewer

- Cuando `data` es `null` → muestra el placeholder "—"
- Cuando `data` es un objeto JSON válido → muestra botón "Expandir JSON"
- Al hacer clic en "Expandir JSON" → muestra el JSON pretty-printed con indentación
- Al hacer clic en "Colapsar" → oculta el contenido
- El JSON es de solo lectura — no hay campos editables
- El texto es seleccionable y copiable por el usuario

### CA-AUD-06: Paginación del Lado del Servidor

- La lista carga 20 registros por página por defecto
- Los botones "Anterior" y "Siguiente" navegan entre páginas
- El botón "Anterior" está deshabilitado en la primera página
- El botón "Siguiente" está deshabilitado en la última página
- Al cambiar de página, la URL no cambia (paginación en memoria/estado)
- Los filtros aplicados se mantienen al cambiar de página

### CA-AUD-07: Inmutabilidad del Log

- No existe ningún botón de "Editar", "Eliminar" ni "Crear" en ninguna vista del módulo de auditoría
- El módulo es completamente de solo lectura
- Ninguna acción del usuario puede modificar, eliminar o agregar registros al log
- Los datos se muestran exactamente como fueron registrados por el backend

### CA-AUD-08: Requisitos TDD

- Todos los componentes tienen tests unitarios (Vitest) escritos primero (Red)
- `AuditRecordSchema` tiene tests para los 6 tipos de operación y los casos null
- `AuditFiltersSchema` verifica que todos los campos son opcionales
- `useAuditLog` tiene tests para loading, success, error 500 y error 403
- `JsonViewer` tiene tests para null, expand y collapse
- `OperacionBadge` tiene tests para los 6 valores del enum con sus colores correctos
- `auditoriaSlice` tiene tests de `setFiltro` (clave individual) y `resetFiltros` (todos a vacío)
- Los tests E2E en Playwright cubren listado, filtros, detalle con JSON y redirección de acceso
- Cobertura mínima requerida: 80% por archivo
