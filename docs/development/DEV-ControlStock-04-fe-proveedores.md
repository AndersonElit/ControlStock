# Etapa 4g — Frontend: Feature Proveedores

---

## 1. Contexto y Objetivo

### Contexto

La feature de **Proveedores** permite la gestión centralizada de los proveedores del sistema ControlStock. Cada proveedor puede tener una configuración de integración asociada (FTP/REST/SFTP) cuyos credenciales se almacenan de forma segura en HashiCorp Vault. El frontend **nunca** expone credenciales reales: solo muestra el `vault_secret_path` como referencia de solo lectura.

Esta etapa cubre el ciclo completo: listado con filtros, creación, visualización de detalle (incluyendo configuración de integración para Administradores), edición y proceso de inactivación.

### Objetivo

Implementar el módulo frontend de Proveedores bajo la arquitectura Next.js 14 App Router con TypeScript estricto, aplicando TDD (Red-Green-Refactor) en cada componente, hook y esquema de validación. Consumir el `supplier-service` expuesto a través del Kong API Gateway en `http://<VPS_IP>:8000/api/v1`.

### Principios Guía

- **TDD estricto**: el test se escribe antes que la implementación. Ciclo Red → Green → Refactor.
- **Seguridad first**: credenciales de integración NUNCA se renderizan. Solo `vaultSecretPath`.
- **RBAC granular**: cada botón, sección y ruta valida el rol antes de renderizar.
- **Type-safety total**: Zod valida en runtime toda respuesta de API. TypeScript estricto.
- **Accesibilidad**: componentes accesibles con atributos `aria-*` y roles ARIA correctos.

---

## 2. Prerrequisitos

### Infraestructura

| Elemento | Detalle |
|---|---|
| Kong API Gateway | `http://<VPS_IP>:8000/api/v1` operativo con rutas de `supplier-service` configuradas |
| supplier-service | Desplegado en K3s, health check OK |
| HashiCorp Vault | Operativo; rutas de secreto accesibles solo por backend |
| Keycloak OIDC | Realm `controlstock` con roles configurados |
| Next.js 14 scaffolding | App Router inicializado (Etapa 4a completada) |

### Dependencias del Proyecto (package.json)

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

- Etapa 4a: Scaffolding Next.js 14 App Router + configuración global
- Etapa 4b: Feature Autenticación (NextAuth + Keycloak)
- Etapa 4c: Feature Dashboard
- Etapa 4d: Feature Categorías
- Etapa 4e: Feature Productos
- Etapa 4f: Feature Inventario

### Convenciones de Archivos

```
src/
  app/
    (protected)/
      proveedores/
        page.tsx                    # ProveedorListPage
        nuevo/
          page.tsx                  # ProveedorFormPage (create)
        [id]/
          page.tsx                  # ProveedorDetailPage
          editar/
            page.tsx                # ProveedorFormPage (edit)
  components/
    proveedores/
      ProveedorTable.tsx
      ProveedorTable.test.tsx
      ProveedorForm.tsx
      ProveedorForm.test.tsx
      ProveedorDetail.tsx
      ProveedorDetail.test.tsx
      IntegracionConfigSection.tsx
      IntegracionConfigSection.test.tsx
      MetodoIntegracionBadge.tsx
      MetodoIntegracionBadge.test.tsx
      InactivarProveedorModal.tsx
      InactivarProveedorModal.test.tsx
      EstadoBadge.tsx
      EstadoBadge.test.tsx
  hooks/
    proveedores/
      useProveedores.ts
      useProveedores.test.ts
      useProveedor.ts
      useProveedor.test.ts
      useCreateProveedor.ts
      useCreateProveedor.test.ts
      useUpdateProveedor.ts
      useUpdateProveedor.test.ts
      useInactivarProveedor.ts
      useInactivarProveedor.test.ts
  store/
    slices/
      proveedoresSlice.ts
      proveedoresSlice.test.ts
  schemas/
    proveedor.schema.ts
    proveedor.schema.test.ts
  types/
    proveedor.types.ts
```

---

## 3. Rutas y Páginas

| Ruta | Tipo | Componente Página | Descripción |
|---|---|---|---|
| `/proveedores` | Protected — todos los roles autenticados | `ProveedorListPage` | Lista paginada de proveedores con filtros por estado y método de integración. Botón "Nuevo Proveedor" visible solo para Administrador. |
| `/proveedores/nuevo` | Protected — solo Administrador | `ProveedorFormPage` (modo create) | Formulario de creación de proveedor. Redirige a `/proveedores` si el rol no es Administrador. |
| `/proveedores/[id]` | Protected — todos los roles autenticados | `ProveedorDetailPage` | Detalle del proveedor. Sección de configuración de integración visible solo para Administrador. |
| `/proveedores/[id]/editar` | Protected — Administrador y Supervisor | `ProveedorFormPage` (modo edit) | Formulario de edición. Supervisor puede editar solo datos básicos (no configuración de integración). |

### Implementación de Páginas

#### `app/(protected)/proveedores/page.tsx`

```typescript
import { Suspense } from 'react'
import { ProveedorListPage } from '@/components/proveedores/ProveedorListPage'
import { PageSkeleton } from '@/components/ui/PageSkeleton'

export const metadata = { title: 'Proveedores — ControlStock' }

export default function Page() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <ProveedorListPage />
    </Suspense>
  )
}
```

#### `app/(protected)/proveedores/[id]/page.tsx`

```typescript
interface Props { params: { id: string } }

export default function Page({ params }: Props) {
  return <ProveedorDetailPage id={params.id} />
}
```

---

## 4. Componentes

> **Nota TDD:** test-first — el test de render/interacción precede al componente. Cada componente listado a continuación tiene su archivo `.test.tsx` escrito y en RED antes de crear el `.tsx` correspondiente.

### 4.1 `ProveedorTable`

**Archivo:** `src/components/proveedores/ProveedorTable.tsx`

**Responsabilidad:** Renderiza la tabla de proveedores con columnas: nombre, identificación fiscal, método de integración (badge), estado (badge), acciones (ver, editar, inactivar según rol).

**Props:**

```typescript
interface ProveedorTableProps {
  proveedores: ProveedorResponse[]
  isLoading: boolean
  onInactivar: (id: string) => void
  rol: UserRole
}
```

**Implementación:**

```typescript
'use client'

import { ProveedorResponse } from '@/types/proveedor.types'
import { MetodoIntegracionBadge } from './MetodoIntegracionBadge'
import { EstadoBadge } from './EstadoBadge'
import { UserRole } from '@/types/auth.types'
import Link from 'next/link'

export function ProveedorTable({ proveedores, isLoading, onInactivar, rol }: ProveedorTableProps) {
  const puedeEditar = ['ADMINISTRADOR', 'SUPERVISOR'].includes(rol)
  const puedeInactivar = rol === 'ADMINISTRADOR'

  if (isLoading) {
    return <div role="status" aria-label="Cargando proveedores">Cargando...</div>
  }

  if (proveedores.length === 0) {
    return (
      <div role="status" data-testid="empty-state">
        No se encontraron proveedores.
      </div>
    )
  }

  return (
    <table aria-label="Lista de proveedores">
      <thead>
        <tr>
          <th scope="col">Nombre</th>
          <th scope="col">Identificación Fiscal</th>
          <th scope="col">Método Integración</th>
          <th scope="col">Estado</th>
          <th scope="col">Acciones</th>
        </tr>
      </thead>
      <tbody>
        {proveedores.map((p) => (
          <tr key={p.id} data-testid={`row-${p.id}`}>
            <td>{p.nombre}</td>
            <td>{p.identificacionFiscal}</td>
            <td><MetodoIntegracionBadge metodo={p.metodoIntegracion} /></td>
            <td><EstadoBadge estado={p.estado} /></td>
            <td>
              <Link href={`/proveedores/${p.id}`} aria-label={`Ver ${p.nombre}`}>Ver</Link>
              {puedeEditar && (
                <Link href={`/proveedores/${p.id}/editar`} aria-label={`Editar ${p.nombre}`}>
                  Editar
                </Link>
              )}
              {puedeInactivar && p.estado === 'ACTIVO' && (
                <button
                  onClick={() => onInactivar(p.id)}
                  aria-label={`Inactivar ${p.nombre}`}
                >
                  Inactivar
                </button>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
```

---

### 4.2 `ProveedorForm`

**Archivo:** `src/components/proveedores/ProveedorForm.tsx`

**Responsabilidad:** Formulario compartido para creación y edición de proveedores. Usa React Hook Form + Zod para validación.

**Props:**

```typescript
interface ProveedorFormProps {
  defaultValues?: Partial<CreateProveedorInput | UpdateProveedorInput>
  onSubmit: (data: CreateProveedorInput | UpdateProveedorInput) => void
  isSubmitting: boolean
  mode: 'create' | 'edit'
  rol: UserRole
}
```

**Campos:**
- `nombre`: text input, requerido, máx 200 chars, label "Nombre del Proveedor"
- `identificacionFiscal`: text input, requerido, máx 50 chars, label "Identificación Fiscal (CUIT/RUT/NIF)"
- `metodoIntegracion`: select [REST, ARCHIVO], requerido, label "Método de Integración"
- `estado`: select [ACTIVO, INACTIVO], visible solo en modo `edit`, label "Estado"

**Implementación:**

```typescript
'use client'

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { CreateProveedorSchema, UpdateProveedorSchema } from '@/schemas/proveedor.schema'

export function ProveedorForm({ defaultValues, onSubmit, isSubmitting, mode, rol }: ProveedorFormProps) {
  const schema = mode === 'create' ? CreateProveedorSchema : UpdateProveedorSchema
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(schema),
    defaultValues,
  })

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="nombre">Nombre del Proveedor</label>
        <input
          id="nombre"
          {...register('nombre')}
          aria-describedby={errors.nombre ? 'nombre-error' : undefined}
          aria-invalid={!!errors.nombre}
        />
        {errors.nombre && (
          <span id="nombre-error" role="alert">{errors.nombre.message}</span>
        )}
      </div>

      <div>
        <label htmlFor="identificacionFiscal">Identificación Fiscal (CUIT/RUT/NIF)</label>
        <input
          id="identificacionFiscal"
          {...register('identificacionFiscal')}
          aria-invalid={!!errors.identificacionFiscal}
        />
        {errors.identificacionFiscal && (
          <span role="alert">{errors.identificacionFiscal.message}</span>
        )}
        <small>Ingrese el identificador fiscal único del proveedor</small>
      </div>

      <div>
        <label htmlFor="metodoIntegracion">Método de Integración</label>
        <select id="metodoIntegracion" {...register('metodoIntegracion')}>
          <option value="">Seleccione...</option>
          <option value="REST">REST</option>
          <option value="ARCHIVO">ARCHIVO</option>
        </select>
        {errors.metodoIntegracion && (
          <span role="alert">{errors.metodoIntegracion.message}</span>
        )}
      </div>

      {mode === 'edit' && (
        <div>
          <label htmlFor="estado">Estado</label>
          <select id="estado" {...register('estado')}>
            <option value="ACTIVO">Activo</option>
            <option value="INACTIVO">Inactivo</option>
          </select>
        </div>
      )}

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Guardando...' : mode === 'create' ? 'Crear Proveedor' : 'Guardar Cambios'}
      </button>
    </form>
  )
}
```

---

### 4.3 `ProveedorDetail`

**Archivo:** `src/components/proveedores/ProveedorDetail.tsx`

**Responsabilidad:** Muestra información completa del proveedor. Incluye `IntegracionConfigSection` solo para Administrador.

**Props:**

```typescript
interface ProveedorDetailProps {
  proveedor: ProveedorResponse
  integracionConfig?: IntegrationConfigResponse
  rol: UserRole
}
```

**Implementación:**

```typescript
'use client'

import { IntegracionConfigSection } from './IntegracionConfigSection'
import { MetodoIntegracionBadge } from './MetodoIntegracionBadge'
import { EstadoBadge } from './EstadoBadge'

export function ProveedorDetail({ proveedor, integracionConfig, rol }: ProveedorDetailProps) {
  const esAdmin = rol === 'ADMINISTRADOR'

  return (
    <article aria-label={`Detalle del proveedor ${proveedor.nombre}`}>
      <section aria-labelledby="info-section">
        <h2 id="info-section">Información del Proveedor</h2>
        <dl>
          <dt>Nombre</dt>
          <dd>{proveedor.nombre}</dd>
          <dt>Identificación Fiscal</dt>
          <dd>{proveedor.identificacionFiscal}</dd>
          <dt>Método de Integración</dt>
          <dd><MetodoIntegracionBadge metodo={proveedor.metodoIntegracion} /></dd>
          <dt>Estado</dt>
          <dd><EstadoBadge estado={proveedor.estado} /></dd>
          <dt>Creado</dt>
          <dd>{new Date(proveedor.createdAt).toLocaleDateString('es-AR')}</dd>
          <dt>Actualizado</dt>
          <dd>{new Date(proveedor.updatedAt).toLocaleDateString('es-AR')}</dd>
        </dl>
      </section>

      {esAdmin && integracionConfig && (
        <IntegracionConfigSection config={integracionConfig} />
      )}
    </article>
  )
}
```

---

### 4.4 `IntegracionConfigSection`

**Archivo:** `src/components/proveedores/IntegracionConfigSection.tsx`

**Responsabilidad:** Muestra la configuración de integración del proveedor. Solo visible para Administrador. Muestra `vaultSecretPath` como referencia de lectura — NUNCA credenciales reales.

**Regla de seguridad:** Este componente NUNCA debe recibir ni mostrar valores de credenciales. Solo muestra la ruta en Vault.

**Props:**

```typescript
interface IntegracionConfigSectionProps {
  config: IntegrationConfigResponse
}
```

**Implementación:**

```typescript
'use client'

import { IntegrationConfigResponse } from '@/types/proveedor.types'

export function IntegracionConfigSection({ config }: IntegracionConfigSectionProps) {
  return (
    <section
      aria-labelledby="integracion-section"
      data-testid="integracion-config-section"
    >
      <h2 id="integracion-section">Configuración de Integración</h2>

      <div role="note" aria-label="Aviso de seguridad">
        <span>Credenciales gestionadas en Vault</span>
        <p>
          Las credenciales de acceso se almacenan de forma segura en HashiCorp Vault.
          Esta sección solo muestra la referencia (path) al secreto, no los valores.
        </p>
      </div>

      <dl>
        <dt>Protocolo</dt>
        <dd data-testid="protocolo">{config.protocolo}</dd>

        {config.endpoint && (
          <>
            <dt>Endpoint</dt>
            <dd data-testid="endpoint">{config.endpoint}</dd>
          </>
        )}

        <dt>Vault Secret Path</dt>
        <dd data-testid="vault-secret-path">
          <code>{config.vaultSecretPath}</code>
        </dd>

        <dt>Configurado el</dt>
        <dd>{new Date(config.createdAt).toLocaleDateString('es-AR')}</dd>
      </dl>
    </section>
  )
}
```

---

### 4.5 `MetodoIntegracionBadge`

**Archivo:** `src/components/proveedores/MetodoIntegracionBadge.tsx`

```typescript
'use client'

interface MetodoIntegracionBadgeProps {
  metodo: 'REST' | 'ARCHIVO'
}

const METODO_CONFIG = {
  REST: { label: 'REST', className: 'badge badge-blue', ariaLabel: 'Integración por REST API' },
  ARCHIVO: { label: 'ARCHIVO', className: 'badge badge-purple', ariaLabel: 'Integración por Archivo' },
} as const

export function MetodoIntegracionBadge({ metodo }: MetodoIntegracionBadgeProps) {
  const config = METODO_CONFIG[metodo]

  return (
    <span
      className={config.className}
      aria-label={config.ariaLabel}
      data-testid={`metodo-badge-${metodo.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

---

### 4.6 `EstadoBadge`

**Archivo:** `src/components/proveedores/EstadoBadge.tsx`

```typescript
'use client'

interface EstadoBadgeProps {
  estado: 'ACTIVO' | 'INACTIVO'
}

const ESTADO_CONFIG = {
  ACTIVO: { label: 'Activo', className: 'badge badge-green', ariaLabel: 'Estado activo' },
  INACTIVO: { label: 'Inactivo', className: 'badge badge-gray', ariaLabel: 'Estado inactivo' },
} as const

export function EstadoBadge({ estado }: EstadoBadgeProps) {
  const config = ESTADO_CONFIG[estado]

  return (
    <span
      className={config.className}
      aria-label={config.ariaLabel}
      data-testid={`estado-badge-${estado.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

---

### 4.7 `InactivarProveedorModal`

**Archivo:** `src/components/proveedores/InactivarProveedorModal.tsx`

**Responsabilidad:** Modal de confirmación para inactivar un proveedor. Solicita confirmación explícita antes de ejecutar la acción.

**Props:**

```typescript
interface InactivarProveedorModalProps {
  proveedor: Pick<ProveedorResponse, 'id' | 'nombre'>
  isOpen: boolean
  onConfirm: () => void
  onCancel: () => void
  isLoading: boolean
}
```

**Implementación:**

```typescript
'use client'

export function InactivarProveedorModal({
  proveedor, isOpen, onConfirm, onCancel, isLoading
}: InactivarProveedorModalProps) {
  if (!isOpen) return null

  return (
    <div role="dialog" aria-modal="true" aria-labelledby="modal-title" data-testid="inactivar-modal">
      <div>
        <h2 id="modal-title">Confirmar Inactivación</h2>
        <p>
          ¿Está seguro que desea inactivar al proveedor{' '}
          <strong>{proveedor.nombre}</strong>?
        </p>
        <p>
          El proveedor quedará inactivo y no podrá ser utilizado en nuevas operaciones.
          Esta acción puede ser revertida por un Administrador.
        </p>

        <div>
          <button onClick={onCancel} disabled={isLoading}>
            Cancelar
          </button>
          <button
            onClick={onConfirm}
            disabled={isLoading}
            aria-busy={isLoading}
            data-testid="confirm-inactivar-btn"
          >
            {isLoading ? 'Inactivando...' : 'Confirmar Inactivación'}
          </button>
        </div>
      </div>
    </div>
  )
}
```

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** test-first — cada hook tiene su archivo `.test.ts` en estado RED antes de implementar el hook. Se usa MSW para interceptar las peticiones HTTP en los tests.

### Configuración Base

**Archivo:** `src/lib/api/proveedores.api.ts`

```typescript
import { ProveedorResponse, IntegrationConfigResponse, CreateProveedorInput, UpdateProveedorInput } from '@/types/proveedor.types'
import { ProveedorResponseSchema, IntegrationConfigResponseSchema } from '@/schemas/proveedor.schema'
import { z } from 'zod'

const BASE_URL = `${process.env.NEXT_PUBLIC_API_URL}/suppliers`

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

export const proveedoresApi = {
  list: async (params?: { estado?: string; metodo?: string; page?: number; size?: number }) => {
    const sp = new URLSearchParams()
    if (params?.estado && params.estado !== 'TODOS') sp.set('estado', params.estado)
    if (params?.metodo && params.metodo !== 'TODOS') sp.set('metodoIntegracion', params.metodo)
    if (params?.page !== undefined) sp.set('page', String(params.page))
    if (params?.size !== undefined) sp.set('size', String(params.size))
    const data = await fetchWithAuth(`${BASE_URL}?${sp}`)
    return z.array(ProveedorResponseSchema).parse(data.content ?? data)
  },

  getById: async (id: string): Promise<ProveedorResponse> => {
    const data = await fetchWithAuth(`${BASE_URL}/${id}`)
    return ProveedorResponseSchema.parse(data)
  },

  create: async (input: CreateProveedorInput): Promise<ProveedorResponse> => {
    const data = await fetchWithAuth(BASE_URL, { method: 'POST', body: JSON.stringify(input) })
    return ProveedorResponseSchema.parse(data)
  },

  update: async (id: string, input: UpdateProveedorInput): Promise<ProveedorResponse> => {
    const data = await fetchWithAuth(`${BASE_URL}/${id}`, { method: 'PUT', body: JSON.stringify(input) })
    return ProveedorResponseSchema.parse(data)
  },

  inactivar: async (id: string): Promise<void> => {
    await fetchWithAuth(`${BASE_URL}/${id}`, { method: 'DELETE' })
  },
}
```

---

### 5.1 `useProveedores`

**Archivo:** `src/hooks/proveedores/useProveedores.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { proveedoresApi } from '@/lib/api/proveedores.api'
import { useProveedoresStore } from '@/store/proveedoresStore'

export const PROVEEDORES_QUERY_KEY = ['proveedores'] as const

export function useProveedores(params?: { page?: number; size?: number }) {
  const { estadoFilter, metodoFilter } = useProveedoresStore()

  return useQuery({
    queryKey: [...PROVEEDORES_QUERY_KEY, estadoFilter, metodoFilter, params],
    queryFn: () => proveedoresApi.list({ estado: estadoFilter, metodo: metodoFilter, ...params }),
    staleTime: 5 * 60 * 1000, // 5 minutos
  })
}
```

---

### 5.2 `useProveedor`

**Archivo:** `src/hooks/proveedores/useProveedor.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { proveedoresApi } from '@/lib/api/proveedores.api'

export const proveedorQueryKey = (id: string) => ['proveedor', id] as const

export function useProveedor(id: string) {
  return useQuery({
    queryKey: proveedorQueryKey(id),
    queryFn: () => proveedoresApi.getById(id),
    enabled: !!id,
    staleTime: 5 * 60 * 1000,
  })
}
```

---

### 5.3 `useCreateProveedor`

**Archivo:** `src/hooks/proveedores/useCreateProveedor.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { proveedoresApi } from '@/lib/api/proveedores.api'
import { PROVEEDORES_QUERY_KEY } from './useProveedores'

export function useCreateProveedor() {
  const queryClient = useQueryClient()
  const router = useRouter()

  return useMutation({
    mutationFn: proveedoresApi.create,
    onSuccess: (newProveedor) => {
      queryClient.invalidateQueries({ queryKey: PROVEEDORES_QUERY_KEY })
      router.push('/proveedores')
    },
    onError: (error: any) => {
      if (error.status === 409) {
        // Duplicado de identificacion fiscal — manejado en la UI
        return
      }
    },
  })
}
```

---

### 5.4 `useUpdateProveedor`

**Archivo:** `src/hooks/proveedores/useUpdateProveedor.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { proveedoresApi } from '@/lib/api/proveedores.api'
import { proveedorQueryKey } from './useProveedor'

export function useUpdateProveedor(id: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: UpdateProveedorInput) => proveedoresApi.update(id, input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: proveedorQueryKey(id) })
    },
  })
}
```

---

### 5.5 `useInactivarProveedor`

**Archivo:** `src/hooks/proveedores/useInactivarProveedor.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { proveedoresApi } from '@/lib/api/proveedores.api'
import { PROVEEDORES_QUERY_KEY } from './useProveedores'

export function useInactivarProveedor(id: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: () => proveedoresApi.inactivar(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: PROVEEDORES_QUERY_KEY })
    },
  })
}
```

---

## 6. Estado Global (Zustand)

> **Nota TDD:** test-first — el test del slice se escribe antes de implementar el store. Se prueba cada acción de forma aislada.

### `proveedoresSlice`

**Archivo:** `src/store/slices/proveedoresSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export type EstadoFilter = 'TODOS' | 'ACTIVO' | 'INACTIVO'
export type MetodoFilter = 'TODOS' | 'REST' | 'ARCHIVO'

export interface ProveedoresSlice {
  estadoFilter: EstadoFilter
  metodoFilter: MetodoFilter
  setEstadoFilter: (filter: EstadoFilter) => void
  setMetodoFilter: (filter: MetodoFilter) => void
  resetFilters: () => void
}

const initialState = {
  estadoFilter: 'TODOS' as EstadoFilter,
  metodoFilter: 'TODOS' as MetodoFilter,
}

export const createProveedoresSlice: StateCreator<ProveedoresSlice> = (set) => ({
  ...initialState,
  setEstadoFilter: (filter) => set({ estadoFilter: filter }),
  setMetodoFilter: (filter) => set({ metodoFilter: filter }),
  resetFilters: () => set(initialState),
})
```

**Archivo:** `src/store/proveedoresStore.ts`

```typescript
import { create } from 'zustand'
import { devtools, persist } from 'zustand/middleware'
import { ProveedoresSlice, createProveedoresSlice } from './slices/proveedoresSlice'

export const useProveedoresStore = create<ProveedoresSlice>()(
  devtools(
    persist(createProveedoresSlice, {
      name: 'controlstock-proveedores-filters',
      partialize: (state) => ({
        estadoFilter: state.estadoFilter,
        metodoFilter: state.metodoFilter,
      }),
    }),
    { name: 'ProveedoresStore' }
  )
)
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** test-first — los tests de schemas se escriben primero, verificando casos válidos, inválidos y edge cases antes de definir los schemas.

**Archivo:** `src/schemas/proveedor.schema.ts`

```typescript
import { z } from 'zod'

// --- Schemas de Input (request) ---

export const CreateProveedorSchema = z.object({
  nombre: z
    .string({ required_error: 'El nombre es requerido' })
    .min(1, 'El nombre no puede estar vacío')
    .max(200, 'El nombre no puede superar 200 caracteres')
    .trim(),
  identificacionFiscal: z
    .string({ required_error: 'La identificación fiscal es requerida' })
    .min(1, 'La identificación fiscal no puede estar vacía')
    .max(50, 'La identificación fiscal no puede superar 50 caracteres')
    .trim(),
  metodoIntegracion: z.enum(['REST', 'ARCHIVO'], {
    required_error: 'El método de integración es requerido',
    invalid_type_error: 'El método de integración debe ser REST o ARCHIVO',
  }),
})

export const UpdateProveedorSchema = CreateProveedorSchema.extend({
  estado: z.enum(['ACTIVO', 'INACTIVO'], {
    required_error: 'El estado es requerido',
  }),
})

// --- Schemas de Response (de la API) ---

export const ProveedorResponseSchema = z.object({
  id: z.string().uuid(),
  nombre: z.string(),
  identificacionFiscal: z.string(),
  metodoIntegracion: z.enum(['REST', 'ARCHIVO']),
  estado: z.enum(['ACTIVO', 'INACTIVO']),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
})

export const IntegrationConfigResponseSchema = z.object({
  id: z.string().uuid(),
  supplierId: z.string().uuid(),
  protocolo: z.enum(['REST', 'FTP', 'SFTP']),
  endpoint: z.string().optional(),
  vaultSecretPath: z.string().min(1, 'La ruta de Vault es requerida'),
  createdAt: z.string().datetime(),
})

// --- Tipos inferidos ---

export type CreateProveedorInput = z.infer<typeof CreateProveedorSchema>
export type UpdateProveedorInput = z.infer<typeof UpdateProveedorSchema>
export type ProveedorResponse = z.infer<typeof ProveedorResponseSchema>
export type IntegrationConfigResponse = z.infer<typeof IntegrationConfigResponseSchema>
```

---

## 8. Autenticación y Autorización

### Roles y Permisos por Acción

| Acción | Administrador | Supervisor | Operador | Gerente | Analista | Auditor |
|---|---|---|---|---|---|---|
| Ver lista proveedores | SI | SI | SI | SI | SI | SI |
| Crear proveedor | SI | NO | NO | NO | NO | NO |
| Editar datos básicos | SI | SI | NO | NO | NO | NO |
| Ver config integración | SI | NO | NO | NO | NO | NO |
| Inactivar proveedor | SI | NO | NO | NO | NO | NO |

### Implementación del Guard de Ruta

**Archivo:** `src/app/(protected)/proveedores/nuevo/page.tsx`

```typescript
import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'

export default async function Page() {
  const session = await getServerSession(authOptions)
  const rol = session?.user?.rol

  if (rol !== 'ADMINISTRADOR') {
    redirect('/proveedores')
  }

  return <ProveedorFormPage mode="create" />
}
```

**Archivo:** `src/app/(protected)/proveedores/[id]/editar/page.tsx`

```typescript
export default async function Page({ params }: { params: { id: string } }) {
  const session = await getServerSession(authOptions)
  const rol = session?.user?.rol

  if (!['ADMINISTRADOR', 'SUPERVISOR'].includes(rol)) {
    redirect(`/proveedores/${params.id}`)
  }

  return <ProveedorFormPage mode="edit" id={params.id} />
}
```

### Hook de Autorización

**Archivo:** `src/hooks/useRolGuard.ts`

```typescript
import { useSession } from 'next-auth/react'

export function useRolGuard(rolesPermitidos: string[]) {
  const { data: session } = useSession()
  const rol = session?.user?.rol ?? ''

  return {
    tieneAcceso: rolesPermitidos.includes(rol),
    rol,
  }
}
```

### Validación en Componentes

```typescript
// En ProveedorListPage
const { tieneAcceso: puedeCrear } = useRolGuard(['ADMINISTRADOR'])
const { tieneAcceso: puedeEditar } = useRolGuard(['ADMINISTRADOR', 'SUPERVISOR'])

// En ProveedorDetailPage
const { tieneAcceso: esAdmin } = useRolGuard(['ADMINISTRADOR'])
// IntegracionConfigSection se renderiza solo si esAdmin === true
```

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Red-Green-Refactor:** Cada test se escribe primero en estado RED (falla porque la implementación no existe). Luego se implementa el código mínimo para que pase (GREEN). Finalmente se refactoriza manteniendo todos los tests en GREEN.

### 9.1 Tests de Schemas (Zod)

**Archivo:** `src/schemas/proveedor.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import {
  CreateProveedorSchema,
  UpdateProveedorSchema,
  ProveedorResponseSchema,
  IntegrationConfigResponseSchema,
} from './proveedor.schema'

describe('CreateProveedorSchema', () => {
  it('valida correctamente un proveedor REST válido', () => {
    const input = {
      nombre: 'Proveedor Tech SRL',
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('valida correctamente un proveedor ARCHIVO válido', () => {
    const input = {
      nombre: 'Distribuidora Norte SA',
      identificacionFiscal: '30-98765432-1',
      metodoIntegracion: 'ARCHIVO',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('falla cuando nombre está ausente', () => {
    const input = {
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].path).toContain('nombre')
  })

  it('falla cuando nombre está vacío', () => {
    const input = {
      nombre: '',
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
  })

  it('falla cuando nombre supera 200 caracteres', () => {
    const input = {
      nombre: 'A'.repeat(201),
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
  })

  it('falla cuando identificacionFiscal está vacía', () => {
    const input = {
      nombre: 'Proveedor Valido',
      identificacionFiscal: '',
      metodoIntegracion: 'REST',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
  })

  it('falla cuando metodoIntegracion es inválido', () => {
    const input = {
      nombre: 'Proveedor Valido',
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'GRAPHQL',
    }
    const result = CreateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
  })
})

describe('UpdateProveedorSchema', () => {
  it('incluye campo estado en la validación', () => {
    const input = {
      nombre: 'Proveedor Actualizado',
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
      estado: 'INACTIVO',
    }
    const result = UpdateProveedorSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('falla cuando estado es inválido', () => {
    const input = {
      nombre: 'Proveedor',
      identificacionFiscal: '20-12345678-9',
      metodoIntegracion: 'REST',
      estado: 'SUSPENDIDO',
    }
    const result = UpdateProveedorSchema.safeParse(input)
    expect(result.success).toBe(false)
  })
})

describe('IntegrationConfigResponseSchema', () => {
  it('valida config REST válida', () => {
    const config = {
      id: '123e4567-e89b-12d3-a456-426614174000',
      supplierId: '123e4567-e89b-12d3-a456-426614174001',
      protocolo: 'REST',
      endpoint: 'https://api.proveedor.com/v1',
      vaultSecretPath: 'secret/suppliers/proveedor-tech/credentials',
      createdAt: '2024-01-15T10:00:00.000Z',
    }
    const result = IntegrationConfigResponseSchema.safeParse(config)
    expect(result.success).toBe(true)
  })

  it('valida config FTP sin endpoint (opcional)', () => {
    const config = {
      id: '123e4567-e89b-12d3-a456-426614174000',
      supplierId: '123e4567-e89b-12d3-a456-426614174001',
      protocolo: 'FTP',
      vaultSecretPath: 'secret/suppliers/distrib-norte/ftp',
      createdAt: '2024-01-15T10:00:00.000Z',
    }
    const result = IntegrationConfigResponseSchema.safeParse(config)
    expect(result.success).toBe(true)
  })
})
```

---

### 9.2 Tests de Hooks API

**Archivo:** `src/hooks/proveedores/useProveedores.test.ts`

```typescript
import { describe, it, expect, beforeAll, afterEach, afterAll } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'
import { createWrapper } from '@/test/utils'
import { useProveedores } from './useProveedores'

const MOCK_PROVEEDORES = [
  {
    id: '1',
    nombre: 'Proveedor A',
    identificacionFiscal: '20-111-1',
    metodoIntegracion: 'REST',
    estado: 'ACTIVO',
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-01T00:00:00.000Z',
  },
]

const server = setupServer(
  http.get('*/api/v1/suppliers', () => {
    return HttpResponse.json({ content: MOCK_PROVEEDORES })
  })
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('useProveedores', () => {
  it('retorna estado de carga inicial', () => {
    const { result } = renderHook(() => useProveedores(), { wrapper: createWrapper() })
    expect(result.current.isLoading).toBe(true)
  })

  it('retorna lista de proveedores correctamente', async () => {
    const { result } = renderHook(() => useProveedores(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toHaveLength(1)
    expect(result.current.data![0].nombre).toBe('Proveedor A')
  })

  it('retorna error cuando el servidor responde 500', async () => {
    server.use(
      http.get('*/api/v1/suppliers', () => HttpResponse.json({ message: 'Error' }, { status: 500 }))
    )
    const { result } = renderHook(() => useProveedores(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isError).toBe(true))
  })
})

describe('useCreateProveedor', () => {
  it('navega a /proveedores e invalida cache en éxito', async () => {
    const mockPush = vi.fn()
    vi.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush }) }))

    server.use(
      http.post('*/api/v1/suppliers', () => HttpResponse.json(MOCK_PROVEEDORES[0], { status: 201 }))
    )

    const { result } = renderHook(() => useCreateProveedor(), { wrapper: createWrapper() })
    result.current.mutate({ nombre: 'Nuevo', identificacionFiscal: '20-999-9', metodoIntegracion: 'REST' })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(mockPush).toHaveBeenCalledWith('/proveedores')
  })

  it('expone error 409 cuando identificacion fiscal está duplicada', async () => {
    server.use(
      http.post('*/api/v1/suppliers', () =>
        HttpResponse.json({ message: 'Identificación fiscal ya existe' }, { status: 409 })
      )
    )

    const { result } = renderHook(() => useCreateProveedor(), { wrapper: createWrapper() })
    result.current.mutate({ nombre: 'Nuevo', identificacionFiscal: '20-111-1', metodoIntegracion: 'REST' })

    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(409)
  })
})
```

---

### 9.3 Tests de Componentes

**Archivo:** `src/components/proveedores/ProveedorTable.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ProveedorTable } from './ProveedorTable'

const mockProveedores = [
  {
    id: '1',
    nombre: 'Tech SRL',
    identificacionFiscal: '20-111-1',
    metodoIntegracion: 'REST' as const,
    estado: 'ACTIVO' as const,
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-01T00:00:00.000Z',
  },
  {
    id: '2',
    nombre: 'Norte SA',
    identificacionFiscal: '30-222-2',
    metodoIntegracion: 'ARCHIVO' as const,
    estado: 'INACTIVO' as const,
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-01T00:00:00.000Z',
  },
]

describe('ProveedorTable', () => {
  it('renderiza filas con todas las columnas correctas', () => {
    render(
      <ProveedorTable
        proveedores={mockProveedores}
        isLoading={false}
        onInactivar={vi.fn()}
        rol="ADMINISTRADOR"
      />
    )

    expect(screen.getByText('Tech SRL')).toBeInTheDocument()
    expect(screen.getByText('20-111-1')).toBeInTheDocument()
    expect(screen.getByTestId('metodo-badge-rest')).toBeInTheDocument()
    expect(screen.getByTestId('estado-badge-activo')).toBeInTheDocument()
  })

  it('muestra mensaje de estado vacío cuando no hay proveedores', () => {
    render(
      <ProveedorTable
        proveedores={[]}
        isLoading={false}
        onInactivar={vi.fn()}
        rol="ADMINISTRADOR"
      />
    )
    expect(screen.getByTestId('empty-state')).toBeInTheDocument()
  })

  it('llama onInactivar con el id correcto al hacer clic en inactivar', async () => {
    const onInactivar = vi.fn()
    render(
      <ProveedorTable
        proveedores={mockProveedores}
        isLoading={false}
        onInactivar={onInactivar}
        rol="ADMINISTRADOR"
      />
    )

    await userEvent.click(screen.getByRole('button', { name: /inactivar tech srl/i }))
    expect(onInactivar).toHaveBeenCalledWith('1')
  })

  it('no muestra botón inactivar para rol Operador', () => {
    render(
      <ProveedorTable
        proveedores={mockProveedores}
        isLoading={false}
        onInactivar={vi.fn()}
        rol="OPERADOR"
      />
    )
    expect(screen.queryByRole('button', { name: /inactivar/i })).not.toBeInTheDocument()
  })
})

describe('MetodoIntegracionBadge', () => {
  it('renderiza badge azul para REST', () => {
    render(<MetodoIntegracionBadge metodo="REST" />)
    const badge = screen.getByTestId('metodo-badge-rest')
    expect(badge).toHaveClass('badge-blue')
  })

  it('renderiza badge morado para ARCHIVO', () => {
    render(<MetodoIntegracionBadge metodo="ARCHIVO" />)
    const badge = screen.getByTestId('metodo-badge-archivo')
    expect(badge).toHaveClass('badge-purple')
  })
})

describe('IntegracionConfigSection', () => {
  const mockConfig = {
    id: '1',
    supplierId: '2',
    protocolo: 'REST' as const,
    endpoint: 'https://api.example.com',
    vaultSecretPath: 'secret/suppliers/tech/creds',
    createdAt: '2024-01-01T00:00:00.000Z',
  }

  it('renderiza la sección con vaultSecretPath cuando el rol es Administrador', () => {
    render(<IntegracionConfigSection config={mockConfig} />)
    expect(screen.getByTestId('integracion-config-section')).toBeInTheDocument()
    expect(screen.getByTestId('vault-secret-path')).toHaveTextContent('secret/suppliers/tech/creds')
  })

  it('muestra hint de seguridad "Credenciales gestionadas en Vault"', () => {
    render(<IntegracionConfigSection config={mockConfig} />)
    expect(screen.getByText(/credenciales gestionadas en vault/i)).toBeInTheDocument()
  })

  it('NO renderiza para rol Supervisor (validado en componente padre)', () => {
    // El padre es quien decide NO renderizar IntegracionConfigSection
    const { container } = render(
      <ProveedorDetail proveedor={mockProveedores[0]} integracionConfig={mockConfig} rol="SUPERVISOR" />
    )
    expect(container.querySelector('[data-testid="integracion-config-section"]')).not.toBeInTheDocument()
  })
})

describe('proveedoresSlice', () => {
  it('setEstadoFilter actualiza el filtro de estado', () => {
    const { result } = renderHook(() => useProveedoresStore())
    act(() => result.current.setEstadoFilter('ACTIVO'))
    expect(result.current.estadoFilter).toBe('ACTIVO')
  })

  it('setMetodoFilter actualiza el filtro de método', () => {
    const { result } = renderHook(() => useProveedoresStore())
    act(() => result.current.setMetodoFilter('REST'))
    expect(result.current.metodoFilter).toBe('REST')
  })

  it('resetFilters devuelve filtros a estado inicial', () => {
    const { result } = renderHook(() => useProveedoresStore())
    act(() => {
      result.current.setEstadoFilter('ACTIVO')
      result.current.setMetodoFilter('REST')
      result.current.resetFilters()
    })
    expect(result.current.estadoFilter).toBe('TODOS')
    expect(result.current.metodoFilter).toBe('TODOS')
  })
})
```

---

## 10. Pruebas E2E (Playwright, ATDD)

**Archivo:** `e2e/proveedores/proveedores.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { loginAs } from '../helpers/auth'
import { mockProveedorApi } from '../helpers/mocks'

test.describe('Feature Proveedores', () => {

  // TC-PROV-01: Administrador crea proveedor y aparece en la lista
  test('TC-PROV-01: Admin crea proveedor y aparece en la lista', async ({ page }) => {
    await loginAs(page, 'admin')
    await mockProveedorApi(page)

    await page.goto('/proveedores/nuevo')

    // Dado que estoy en el formulario de creación
    await expect(page.getByRole('heading', { name: /nuevo proveedor/i })).toBeVisible()

    // Cuando completo los campos y envío
    await page.getByLabel('Nombre del Proveedor').fill('Proveedor E2E Test')
    await page.getByLabel('Identificación Fiscal').fill('20-99999999-9')
    await page.getByLabel('Método de Integración').selectOption('REST')
    await page.getByRole('button', { name: /crear proveedor/i }).click()

    // Entonces soy redirigido a la lista y el proveedor aparece
    await expect(page).toHaveURL('/proveedores')
    await expect(page.getByText('Proveedor E2E Test')).toBeVisible()
    await expect(page.getByTestId('metodo-badge-rest')).toBeVisible()
  })

  // TC-PROV-02: Admin ve detalle y sección de integración con vaultSecretPath
  test('TC-PROV-02: Admin ve sección de configuración de integración con vaultSecretPath', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/proveedores/test-supplier-id')

    // Dado que soy Administrador viendo el detalle
    // Cuando cargo la página
    // Entonces veo la sección de integración
    await expect(page.getByTestId('integracion-config-section')).toBeVisible()
    await expect(page.getByTestId('vault-secret-path')).toBeVisible()

    // Y el vaultSecretPath es un path, no un secreto
    const vaultPath = await page.getByTestId('vault-secret-path').textContent()
    expect(vaultPath).toMatch(/^secret\//)

    // Y se muestra el aviso de seguridad
    await expect(page.getByText(/credenciales gestionadas en vault/i)).toBeVisible()
  })

  // TC-PROV-03: Supervisor NO ve sección de integración en detalle
  test('TC-PROV-03: Supervisor no puede ver la sección de configuración de integración', async ({ page }) => {
    await loginAs(page, 'supervisor')

    await page.goto('/proveedores/test-supplier-id')

    // Dado que soy Supervisor
    // Cuando accedo al detalle de un proveedor
    await expect(page.getByRole('heading', { name: /información del proveedor/i })).toBeVisible()

    // Entonces NO veo la sección de integración
    await expect(page.getByTestId('integracion-config-section')).not.toBeVisible()
  })

  // TC-PROV-04: Admin inactiva proveedor y aparece como INACTIVO en la lista
  test('TC-PROV-04: Admin inactiva proveedor y estado cambia a INACTIVO en la lista', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/proveedores')

    // Dado que veo la lista de proveedores activos
    const row = page.getByTestId('row-supplier-activo-id')
    await expect(row).toBeVisible()

    // Cuando hago clic en "Inactivar" del proveedor
    await row.getByRole('button', { name: /inactivar/i }).click()

    // Y confirmo en el modal
    const modal = page.getByRole('dialog', { name: /confirmar inactivación/i })
    await expect(modal).toBeVisible()
    await modal.getByTestId('confirm-inactivar-btn').click()

    // Entonces el proveedor aparece como INACTIVO en la lista
    await expect(page.getByTestId('estado-badge-inactivo')).toBeVisible()
  })

  // TC-PROV-05: Operador no ve botón "Nuevo Proveedor"
  test('TC-PROV-05: Operador accede a /proveedores y no ve botón de creación', async ({ page }) => {
    await loginAs(page, 'operador')

    await page.goto('/proveedores')

    // Dado que soy un Operador
    // Cuando cargo la lista de proveedores
    await expect(page.getByRole('heading', { name: /proveedores/i })).toBeVisible()

    // Entonces NO veo el botón "Nuevo Proveedor"
    await expect(page.getByRole('link', { name: /nuevo proveedor/i })).not.toBeVisible()
  })
})
```

**Archivo:** `e2e/helpers/auth.ts`

```typescript
export async function loginAs(page: Page, role: 'admin' | 'supervisor' | 'operador' | 'gerente' | 'analista' | 'auditor') {
  const credentials = {
    admin: { email: 'admin@controlstock.test', password: 'Admin123!' },
    supervisor: { email: 'supervisor@controlstock.test', password: 'Sup123!' },
    operador: { email: 'operador@controlstock.test', password: 'Op123!' },
    gerente: { email: 'gerente@controlstock.test', password: 'Ger123!' },
    analista: { email: 'analista@controlstock.test', password: 'Ana123!' },
    auditor: { email: 'auditor@controlstock.test', password: 'Aud123!' },
  }

  await page.goto('/auth/signin')
  await page.getByLabel('Email').fill(credentials[role].email)
  await page.getByLabel('Contraseña').fill(credentials[role].password)
  await page.getByRole('button', { name: /iniciar sesión/i }).click()
  await page.waitForURL('/dashboard')
}
```

---

## 11. Criterios de Aceptación

### CA-PROV-01: Listado de Proveedores

- **Dado** que soy un usuario autenticado con cualquier rol
- **Cuando** navego a `/proveedores`
- **Entonces** veo la lista de proveedores con columnas: nombre, identificación fiscal, método de integración (badge), estado (badge), acciones
- **Y** puedo filtrar por estado (TODOS, ACTIVO, INACTIVO)
- **Y** puedo filtrar por método de integración (TODOS, REST, ARCHIVO)

### CA-PROV-02: Creación de Proveedor (solo Administrador)

- **Dado** que soy Administrador
- **Cuando** completo el formulario de nuevo proveedor con nombre, identificación fiscal y método de integración válidos
- **Y** hago clic en "Crear Proveedor"
- **Entonces** el proveedor se crea y soy redirigido a la lista
- **Y** el nuevo proveedor aparece en la lista con estado ACTIVO
- **Si** la identificación fiscal ya existe, el sistema muestra mensaje de error de duplicado

### CA-PROV-03: Seguridad en Configuración de Integración

- **Dado** que soy Administrador viendo el detalle de un proveedor
- **Cuando** el proveedor tiene configuración de integración
- **Entonces** veo el protocolo, endpoint (si aplica) y el `vaultSecretPath` como path de referencia
- **Y** NUNCA se muestran credenciales, tokens, contraseñas o secrets reales
- **Y** se muestra el aviso "Credenciales gestionadas en Vault"
- **Si** soy Supervisor u otro rol, la sección de integración NO se renderiza

### CA-PROV-04: Control de Acceso por Rol

| Rol | /proveedores | /proveedores/nuevo | /proveedores/[id] | /proveedores/[id]/editar | Sección Integración |
|---|---|---|---|---|---|
| Administrador | Acceso + Botones full | Acceso | Acceso | Acceso | Visible |
| Supervisor | Acceso + Editar | Redirige | Acceso | Acceso | Oculta |
| Operador | Acceso (solo ver) | Redirige | Acceso | Redirige | Oculta |
| Gerente | Acceso (solo ver) | Redirige | Acceso | Redirige | Oculta |
| Analista | Acceso (solo ver) | Redirige | Acceso | Redirige | Oculta |
| Auditor | Acceso (solo ver) | Redirige | Acceso | Redirige | Oculta |

### CA-PROV-05: Inactivación de Proveedor

- **Dado** que soy Administrador
- **Cuando** hago clic en "Inactivar" en un proveedor ACTIVO
- **Entonces** se muestra modal de confirmación con nombre del proveedor
- **Cuando** confirmo la inactivación
- **Entonces** el proveedor pasa a estado INACTIVO en la lista
- **Y** el badge de estado cambia a gris "Inactivo"

### CA-PROV-06: Validación de Formulario

- El campo `nombre` es obligatorio (mín 1, máx 200 caracteres)
- El campo `identificacionFiscal` es obligatorio (mín 1, máx 50 caracteres)
- El campo `metodoIntegracion` debe ser REST o ARCHIVO
- Errores de validación se muestran inline bajo cada campo con `role="alert"`
- El botón submit está deshabilitado durante el envío (`aria-busy`)

### CA-PROV-07: Requisitos TDD

- Todos los componentes tienen tests unitarios escritos en Vitest con ciclo Red-Green-Refactor
- Todos los hooks tienen tests con MSW interceptando requests HTTP
- Todos los schemas Zod tienen tests de casos válidos e inválidos
- El slice de Zustand tiene tests de cada acción
- Todas las rutas críticas tienen tests E2E en Playwright siguiendo ATDD
- Cobertura mínima requerida: 80% por archivo
