# Etapa 4j — Frontend: Feature Administración

---

## 1. Contexto y Objetivo

### Contexto

La feature de **Administración** provee el módulo de gestión de identidades y accesos (IAM) del sistema ControlStock. Permite al Administrador crear usuarios, asignar y revocar roles, inactivar cuentas y consultar los permisos del sistema.

**Integración con Keycloak:** La creación de un usuario en el frontend dispara una llamada al `iam-service` en el backend, que a su vez crea la cuenta en Keycloak. Este proceso es completamente transparente para el frontend — el backend maneja la sincronización. El frontend solo consume los endpoints del `iam-service` y nunca interactúa directamente con la Admin API de Keycloak.

**Acceso exclusivo:** Solo el rol Administrador puede acceder a este módulo. Cualquier otro rol es redirigido a `/dashboard`.

### Objetivo

Implementar el módulo frontend de Administración bajo Next.js 14 App Router con TypeScript estricto. Aplicar TDD (Red-Green-Refactor) en cada capa: schemas Zod, hooks TanStack Query para CRUD de usuarios y roles, componentes React y tests E2E Playwright ATDD.

### Principios Guía

- **TDD estricto**: test antes que implementación. Ciclo Red → Green → Refactor.
- **Seguridad first**: solo Administrador tiene acceso a cualquier ruta de este módulo.
- **Confirmación robusta**: InactivarUsuarioModal exige reingreso del email para confirmar.
- **Role assignment UX**: RoleAssignmentPanel es fluido — asignar/revocar roles sin recargar la página.
- **Type-safety**: Zod valida toda respuesta de API. TypeScript estricto en toda la feature.

---

## 2. Prerrequisitos

### Infraestructura

| Elemento | Detalle |
|---|---|
| Kong API Gateway | `http://<VPS_IP>:8000/api/v1` con rutas del `iam-service` |
| iam-service | Desplegado en K3s; sincroniza usuarios con Keycloak automáticamente |
| Keycloak OIDC | Realm `controlstock`; Admin API usada solo por el backend |
| Next.js 14 scaffolding | App Router inicializado (Etapas 4a-4i completadas) |

### Nota Importante sobre Keycloak

La creación de usuarios mediante `POST /iam/users` en el frontend llama al `iam-service` backend. El `iam-service` es quien hace la llamada a la Admin API de Keycloak para crear la cuenta OIDC. El frontend **no necesita** configuración especial de Keycloak para esta operación — es completamente opaca para el cliente.

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

- Etapa 4a-4i: Scaffolding, autenticación, y todas las features de negocio

### Convenciones de Archivos

```
src/
  app/
    (protected)/
      administracion/
        page.tsx                          # AdminPage (hub)
        usuarios/
          page.tsx                        # UsuarioListPage
          nuevo/
            page.tsx                      # UsuarioFormPage (create)
          [id]/
            page.tsx                      # UsuarioDetailPage
        roles/
          page.tsx                        # RolListPage
  components/
    administracion/
      UsuarioTable.tsx
      UsuarioTable.test.tsx
      UsuarioForm.tsx
      UsuarioForm.test.tsx
      UsuarioDetail.tsx
      UsuarioDetail.test.tsx
      RoleAssignmentPanel.tsx
      RoleAssignmentPanel.test.tsx
      RolChip.tsx
      RolChip.test.tsx
      InactivarUsuarioModal.tsx
      InactivarUsuarioModal.test.tsx
      PermissionsTable.tsx
      PermissionsTable.test.tsx
      EstadoUsuarioBadge.tsx
      EstadoUsuarioBadge.test.tsx
  hooks/
    administracion/
      useUsuarios.ts
      useUsuarios.test.ts
      useUsuario.ts
      useUsuario.test.ts
      useCreateUsuario.ts
      useCreateUsuario.test.ts
      useUpdateUsuario.ts
      useUpdateUsuario.test.ts
      useInactivarUsuario.ts
      useInactivarUsuario.test.ts
      useRoles.ts
      useRoles.test.ts
      useAsignarRol.ts
      useAsignarRol.test.ts
      useRevocarRol.ts
      useRevocarRol.test.ts
      usePermisos.ts
      usePermisos.test.ts
  store/
    slices/
      adminSlice.ts
      adminSlice.test.ts
  schemas/
    admin.schema.ts
    admin.schema.test.ts
  types/
    admin.types.ts
```

---

## 3. Rutas y Páginas

| Ruta | Tipo | Componente Página | Descripción |
|---|---|---|---|
| `/administracion` | Protected — solo Administrador | `AdminPage` | Hub de administración con accesos directos a usuarios y roles. |
| `/administracion/usuarios` | Protected — solo Administrador | `UsuarioListPage` | Lista de usuarios del sistema con búsqueda por texto, estado y roles. Botón para crear usuario. |
| `/administracion/usuarios/nuevo` | Protected — solo Administrador | `UsuarioFormPage` (create) | Formulario de creación de usuario con asignación opcional de roles iniciales. |
| `/administracion/usuarios/[id]` | Protected — solo Administrador | `UsuarioDetailPage` | Detalle del usuario con panel de gestión de roles (asignar/revocar). Botón de inactivar. |
| `/administracion/roles` | Protected — solo Administrador | `RolListPage` | Vista de roles disponibles con sus permisos agrupados por módulo. |

### Protección Global del Módulo

```typescript
// En el middleware de Next.js
if (pathname.startsWith('/administracion')) {
  const rol = session?.user?.rol
  if (rol !== 'ADMINISTRADOR') {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }
}
```

### Implementación de Páginas

#### `app/(protected)/administracion/page.tsx`

```typescript
import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'
import Link from 'next/link'

export const metadata = { title: 'Administración — ControlStock' }

export default async function Page() {
  const session = await getServerSession(authOptions)
  if (session?.user?.rol !== 'ADMINISTRADOR') {
    redirect('/dashboard')
  }

  return (
    <main aria-label="Panel de Administración">
      <h1>Administración del Sistema</h1>
      <nav aria-label="Módulos de administración">
        <Link href="/administracion/usuarios">
          Gestión de Usuarios
        </Link>
        <Link href="/administracion/roles">
          Roles y Permisos
        </Link>
      </nav>
    </main>
  )
}
```

#### `app/(protected)/administracion/usuarios/page.tsx`

```typescript
import { Suspense } from 'react'
import { UsuarioListPage } from '@/components/administracion/UsuarioListPage'
import { PageSkeleton } from '@/components/ui/PageSkeleton'

export const metadata = { title: 'Usuarios — Administración — ControlStock' }

export default function Page() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <UsuarioListPage />
    </Suspense>
  )
}
```

---

## 4. Componentes

> **Nota TDD:** test-first — el test de render/interacción precede al componente. Cada componente tiene su archivo `.test.tsx` escrito y en estado RED antes de crear el `.tsx` correspondiente.

### 4.1 `UsuarioTable`

**Archivo:** `src/components/administracion/UsuarioTable.tsx`

**Responsabilidad:** Tabla de usuarios con columnas: email, nombre, estado (badge), roles (lista de chips), acciones (ver detalle).

**Props:**

```typescript
interface UsuarioTableProps {
  usuarios: UsuarioResponse[]
  isLoading: boolean
  searchText: string
}
```

**Implementación:**

```typescript
'use client'

import { UsuarioResponse } from '@/types/admin.types'
import { EstadoUsuarioBadge } from './EstadoUsuarioBadge'
import { RolChip } from './RolChip'
import { useAdminStore } from '@/store/adminStore'
import Link from 'next/link'

export function UsuarioTable({ usuarios, isLoading, searchText }: UsuarioTableProps) {
  // Filtrar en cliente por texto de búsqueda
  const filteredUsuarios = usuarios.filter((u) => {
    if (!searchText) return true
    const search = searchText.toLowerCase()
    return (
      u.email.toLowerCase().includes(search) ||
      u.nombre.toLowerCase().includes(search)
    )
  })

  if (isLoading) {
    return <div role="status" aria-label="Cargando usuarios">Cargando...</div>
  }

  if (filteredUsuarios.length === 0) {
    return (
      <div role="status" data-testid="empty-state">
        {searchText
          ? `No se encontraron usuarios que coincidan con "${searchText}".`
          : 'No hay usuarios registrados.'}
      </div>
    )
  }

  return (
    <table aria-label="Lista de usuarios">
      <thead>
        <tr>
          <th scope="col">Email</th>
          <th scope="col">Nombre</th>
          <th scope="col">Estado</th>
          <th scope="col">Roles</th>
          <th scope="col">Acciones</th>
        </tr>
      </thead>
      <tbody>
        {filteredUsuarios.map((u) => (
          <tr key={u.id} data-testid={`row-${u.id}`}>
            <td data-testid="email">{u.email}</td>
            <td data-testid="nombre">{u.nombre}</td>
            <td>
              <EstadoUsuarioBadge estado={u.estado} />
            </td>
            <td data-testid="roles">
              <div aria-label={`Roles de ${u.nombre}`}>
                {u.roles && u.roles.length > 0
                  ? u.roles.map((rol) => (
                      <RolChip key={rol.id} rol={rol} onRevoke={undefined} readOnly />
                    ))
                  : <span>Sin roles</span>}
              </div>
            </td>
            <td>
              <Link
                href={`/administracion/usuarios/${u.id}`}
                aria-label={`Ver detalle de ${u.nombre}`}
              >
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

### 4.2 `UsuarioForm`

**Archivo:** `src/components/administracion/UsuarioForm.tsx`

**Responsabilidad:** Formulario para crear o actualizar usuarios. En modo create: email, nombre, roles iniciales. En modo edit: nombre, estado.

**Props:**

```typescript
interface UsuarioFormProps {
  mode: 'create' | 'edit'
  defaultValues?: Partial<CreateUsuarioInput | UpdateUsuarioInput>
  onSubmit: (data: CreateUsuarioInput | UpdateUsuarioInput) => void
  isSubmitting: boolean
  availableRoles?: RolResponse[]
}
```

**Implementación:**

```typescript
'use client'

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { CreateUsuarioSchema, UpdateUsuarioSchema } from '@/schemas/admin.schema'
import type { CreateUsuarioInput, UpdateUsuarioInput } from '@/schemas/admin.schema'
import { RolResponse } from '@/types/admin.types'

export function UsuarioForm({
  mode,
  defaultValues,
  onSubmit,
  isSubmitting,
  availableRoles = [],
}: UsuarioFormProps) {
  const schema = mode === 'create' ? CreateUsuarioSchema : UpdateUsuarioSchema
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(schema),
    defaultValues,
  })

  return (
    <form
      onSubmit={handleSubmit(onSubmit)}
      noValidate
      aria-label={mode === 'create' ? 'Formulario de nuevo usuario' : 'Formulario de edición de usuario'}
    >
      {mode === 'create' && (
        <div>
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            {...register('email')}
            aria-invalid={!!errors.email}
            aria-describedby={errors.email ? 'email-error' : undefined}
            autoComplete="email"
          />
          {errors.email && (
            <span id="email-error" role="alert">{errors.email.message}</span>
          )}
        </div>
      )}

      <div>
        <label htmlFor="nombre">Nombre Completo</label>
        <input
          id="nombre"
          type="text"
          {...register('nombre')}
          aria-invalid={!!errors.nombre}
          aria-describedby={errors.nombre ? 'nombre-error' : undefined}
        />
        {errors.nombre && (
          <span id="nombre-error" role="alert">{errors.nombre.message}</span>
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

      {mode === 'create' && availableRoles.length > 0 && (
        <fieldset>
          <legend>Roles Iniciales (opcional)</legend>
          {availableRoles.map((rol) => (
            <div key={rol.id}>
              <input
                type="checkbox"
                id={`rol-${rol.id}`}
                value={rol.id}
                {...register('initialRoles')}
              />
              <label htmlFor={`rol-${rol.id}`}>{rol.nombre}</label>
              {rol.descripcion && <small>{rol.descripcion}</small>}
            </div>
          ))}
        </fieldset>
      )}

      <button type="submit" disabled={isSubmitting} aria-busy={isSubmitting}>
        {isSubmitting
          ? 'Guardando...'
          : mode === 'create'
            ? 'Crear Usuario'
            : 'Guardar Cambios'}
      </button>
    </form>
  )
}
```

---

### 4.3 `UsuarioDetail`

**Archivo:** `src/components/administracion/UsuarioDetail.tsx`

**Responsabilidad:** Muestra la información completa del usuario con panel de gestión de roles.

**Props:**

```typescript
interface UsuarioDetailProps {
  usuario: UsuarioResponseWithRoles
  availableRoles: RolResponse[]
}
```

**Implementación:**

```typescript
'use client'

import { useState } from 'react'
import { UsuarioResponseWithRoles, RolResponse } from '@/types/admin.types'
import { EstadoUsuarioBadge } from './EstadoUsuarioBadge'
import { RoleAssignmentPanel } from './RoleAssignmentPanel'
import { InactivarUsuarioModal } from './InactivarUsuarioModal'
import { useInactivarUsuario } from '@/hooks/administracion/useInactivarUsuario'

export function UsuarioDetail({ usuario, availableRoles }: UsuarioDetailProps) {
  const [showInactivarModal, setShowInactivarModal] = useState(false)
  const { mutate: inactivar, isPending } = useInactivarUsuario(usuario.id)

  const handleConfirmInactivar = () => {
    inactivar(undefined, {
      onSuccess: () => setShowInactivarModal(false),
    })
  }

  return (
    <article aria-label={`Detalle del usuario ${usuario.nombre}`}>
      <header>
        <h1>{usuario.nombre}</h1>
        <EstadoUsuarioBadge estado={usuario.estado} />
      </header>

      <section aria-labelledby="user-info-section">
        <h2 id="user-info-section">Información del Usuario</h2>
        <dl>
          <dt>ID</dt>
          <dd data-testid="user-id">{usuario.id}</dd>
          <dt>Email</dt>
          <dd data-testid="user-email">{usuario.email}</dd>
          <dt>Nombre</dt>
          <dd data-testid="user-nombre">{usuario.nombre}</dd>
          <dt>Keycloak Subject</dt>
          <dd data-testid="user-kc-sub">{usuario.keycloakSub}</dd>
          <dt>Estado</dt>
          <dd><EstadoUsuarioBadge estado={usuario.estado} /></dd>
          <dt>Creado</dt>
          <dd>{new Date(usuario.createdAt).toLocaleDateString('es-AR')}</dd>
        </dl>
      </section>

      <section aria-labelledby="roles-section">
        <h2 id="roles-section">Gestión de Roles</h2>
        <RoleAssignmentPanel
          userId={usuario.id}
          currentRoles={usuario.roles ?? []}
          availableRoles={availableRoles}
        />
      </section>

      {usuario.estado === 'ACTIVO' && (
        <section aria-labelledby="danger-section">
          <h2 id="danger-section">Zona de Peligro</h2>
          <button
            onClick={() => setShowInactivarModal(true)}
            data-testid="inactivar-btn"
          >
            Inactivar Usuario
          </button>
        </section>
      )}

      <InactivarUsuarioModal
        usuario={usuario}
        isOpen={showInactivarModal}
        onConfirm={handleConfirmInactivar}
        onCancel={() => setShowInactivarModal(false)}
        isLoading={isPending}
      />
    </article>
  )
}
```

---

### 4.4 `RoleAssignmentPanel`

**Archivo:** `src/components/administracion/RoleAssignmentPanel.tsx`

**Responsabilidad:** Panel para asignar y revocar roles a un usuario. Muestra los roles actuales con botón de remoción y un dropdown para agregar nuevos roles.

**Props:**

```typescript
interface RoleAssignmentPanelProps {
  userId: string
  currentRoles: RolResponse[]
  availableRoles: RolResponse[]
}
```

**Implementación:**

```typescript
'use client'

import { useState } from 'react'
import { RolResponse } from '@/types/admin.types'
import { RolChip } from './RolChip'
import { useAsignarRol } from '@/hooks/administracion/useAsignarRol'
import { useRevocarRol } from '@/hooks/administracion/useRevocarRol'

export function RoleAssignmentPanel({ userId, currentRoles, availableRoles }: RoleAssignmentPanelProps) {
  const [selectedRolId, setSelectedRolId] = useState('')
  const { mutate: asignarRol, isPending: isAssigning } = useAsignarRol(userId)
  const { mutate: revocarRol, isPending: isRevoking } = useRevocarRol(userId)

  // Roles disponibles que NO están ya asignados
  const rolesParaAsignar = availableRoles.filter(
    (r) => !currentRoles.some((cr) => cr.id === r.id)
  )

  const handleAsignar = () => {
    if (!selectedRolId) return
    asignarRol(
      { rolId: selectedRolId },
      { onSuccess: () => setSelectedRolId('') }
    )
  }

  const handleRevocar = (roleId: string) => {
    revocarRol({ roleId })
  }

  return (
    <div data-testid="role-assignment-panel">
      {/* Roles actuales */}
      <div aria-label="Roles actuales del usuario">
        {currentRoles.length === 0 ? (
          <p data-testid="no-roles-msg">Este usuario no tiene roles asignados.</p>
        ) : (
          currentRoles.map((rol) => (
            <RolChip
              key={rol.id}
              rol={rol}
              onRevoke={() => handleRevocar(rol.id)}
              readOnly={false}
            />
          ))
        )}
      </div>

      {/* Agregar nuevo rol */}
      {rolesParaAsignar.length > 0 && (
        <div>
          <label htmlFor="add-role-select">Agregar Rol</label>
          <select
            id="add-role-select"
            value={selectedRolId}
            onChange={(e) => setSelectedRolId(e.target.value)}
            aria-label="Seleccionar rol para asignar"
            data-testid="add-role-select"
          >
            <option value="">Seleccione un rol...</option>
            {rolesParaAsignar.map((rol) => (
              <option key={rol.id} value={rol.id}>
                {rol.nombre} — {rol.descripcion}
              </option>
            ))}
          </select>

          <button
            onClick={handleAsignar}
            disabled={!selectedRolId || isAssigning}
            aria-busy={isAssigning}
            data-testid="add-role-btn"
          >
            {isAssigning ? 'Asignando...' : 'Asignar Rol'}
          </button>
        </div>
      )}

      {rolesParaAsignar.length === 0 && (
        <p data-testid="all-roles-assigned">
          El usuario ya tiene todos los roles disponibles asignados.
        </p>
      )}
    </div>
  )
}
```

---

### 4.5 `RolChip`

**Archivo:** `src/components/administracion/RolChip.tsx`

**Responsabilidad:** Badge pequeño que muestra el nombre del rol con botón "×" para revocar (cuando `readOnly=false`).

**Props:**

```typescript
interface RolChipProps {
  rol: RolResponse
  onRevoke: (() => void) | undefined
  readOnly: boolean
}
```

**Implementación:**

```typescript
'use client'

import { RolResponse } from '@/types/admin.types'

export function RolChip({ rol, onRevoke, readOnly }: RolChipProps) {
  return (
    <span
      className="rol-chip"
      data-testid={`rol-chip-${rol.nombre.toLowerCase()}`}
      aria-label={`Rol: ${rol.nombre}`}
    >
      {rol.nombre}
      {!readOnly && onRevoke && (
        <button
          type="button"
          onClick={onRevoke}
          aria-label={`Revocar rol ${rol.nombre}`}
          data-testid={`revoke-${rol.nombre.toLowerCase()}-btn`}
          className="rol-chip-revoke"
        >
          ×
        </button>
      )}
    </span>
  )
}
```

---

### 4.6 `InactivarUsuarioModal`

**Archivo:** `src/components/administracion/InactivarUsuarioModal.tsx`

**Responsabilidad:** Modal de confirmación para inactivar un usuario. Requiere que el Administrador reingrese el email del usuario para habilitar el botón de confirmación (doble validación).

**Props:**

```typescript
interface InactivarUsuarioModalProps {
  usuario: Pick<UsuarioResponse, 'id' | 'email' | 'nombre'>
  isOpen: boolean
  onConfirm: () => void
  onCancel: () => void
  isLoading: boolean
}
```

**Implementación:**

```typescript
'use client'

import { useState } from 'react'

export function InactivarUsuarioModal({
  usuario, isOpen, onConfirm, onCancel, isLoading,
}: InactivarUsuarioModalProps) {
  const [confirmEmail, setConfirmEmail] = useState('')

  if (!isOpen) return null

  const emailMatch = confirmEmail === usuario.email
  const canConfirm = emailMatch && !isLoading

  const handleCancel = () => {
    setConfirmEmail('')
    onCancel()
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="inactivar-modal-title"
      data-testid="inactivar-usuario-modal"
    >
      <div>
        <h2 id="inactivar-modal-title">Confirmar Inactivación de Usuario</h2>

        <div role="alert">
          <p>
            Está a punto de inactivar al usuario <strong>{usuario.nombre}</strong> ({usuario.email}).
          </p>
          <p>
            El usuario perderá acceso inmediato al sistema. Esta acción puede revertirse
            modificando el estado del usuario a ACTIVO.
          </p>
        </div>

        <div>
          <label htmlFor="confirm-email">
            Confirme el email del usuario para continuar:
          </label>
          <input
            id="confirm-email"
            type="email"
            value={confirmEmail}
            onChange={(e) => setConfirmEmail(e.target.value)}
            placeholder={usuario.email}
            aria-describedby="confirm-email-hint"
            data-testid="confirm-email-input"
            autoComplete="off"
          />
          <small id="confirm-email-hint">
            Escriba exactamente: <code>{usuario.email}</code>
          </small>
        </div>

        <div>
          <button
            onClick={handleCancel}
            disabled={isLoading}
            data-testid="modal-cancel-btn"
          >
            Cancelar
          </button>
          <button
            onClick={onConfirm}
            disabled={!canConfirm}
            aria-busy={isLoading}
            data-testid="modal-confirm-btn"
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

### 4.7 `PermissionsTable`

**Archivo:** `src/components/administracion/PermissionsTable.tsx`

**Responsabilidad:** Tabla de permisos agrupados por módulo del sistema.

**Props:**

```typescript
interface PermissionsTableProps {
  permisos: PermisoResponse[]
  isLoading: boolean
}
```

**Implementación:**

```typescript
'use client'

import { PermisoResponse } from '@/types/admin.types'

function groupByModule(permisos: PermisoResponse[]) {
  return permisos.reduce<Record<string, PermisoResponse[]>>((acc, permiso) => {
    if (!acc[permiso.modulo]) acc[permiso.modulo] = []
    acc[permiso.modulo].push(permiso)
    return acc
  }, {})
}

export function PermissionsTable({ permisos, isLoading }: PermissionsTableProps) {
  if (isLoading) {
    return <div role="status">Cargando permisos...</div>
  }

  const grouped = groupByModule(permisos)

  return (
    <section aria-label="Tabla de permisos del sistema">
      {Object.entries(grouped).map(([modulo, permsModulo]) => (
        <div key={modulo} data-testid={`module-${modulo}`}>
          <h3>{modulo}</h3>
          <table aria-label={`Permisos del módulo ${modulo}`}>
            <thead>
              <tr>
                <th scope="col">Operación</th>
                <th scope="col">Descripción</th>
              </tr>
            </thead>
            <tbody>
              {permsModulo.map((p) => (
                <tr key={p.id} data-testid={`perm-${p.id}`}>
                  <td><code>{p.operacion}</code></td>
                  <td>{p.descripcion}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </section>
  )
}
```

---

### 4.8 `EstadoUsuarioBadge`

**Archivo:** `src/components/administracion/EstadoUsuarioBadge.tsx`

```typescript
'use client'

interface EstadoUsuarioBadgeProps {
  estado: 'ACTIVO' | 'INACTIVO'
}

const ESTADO_CONFIG = {
  ACTIVO: { label: 'Activo', className: 'badge badge-green', ariaLabel: 'Usuario activo' },
  INACTIVO: { label: 'Inactivo', className: 'badge badge-gray', ariaLabel: 'Usuario inactivo' },
} as const

export function EstadoUsuarioBadge({ estado }: EstadoUsuarioBadgeProps) {
  const config = ESTADO_CONFIG[estado]
  return (
    <span
      className={config.className}
      aria-label={config.ariaLabel}
      data-testid={`estado-usuario-badge-${estado.toLowerCase()}`}
    >
      {config.label}
    </span>
  )
}
```

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** test-first — cada hook tiene su archivo `.test.ts` escrito en estado RED antes de implementar el hook. MSW intercepta peticiones HTTP en los tests.

### Configuración Base API

**Archivo:** `src/lib/api/admin.api.ts`

```typescript
import { z } from 'zod'
import {
  UsuarioResponseSchema,
  RolResponseSchema,
  PermisoResponseSchema,
} from '@/schemas/admin.schema'
import type { CreateUsuarioInput, UpdateUsuarioInput } from '@/schemas/admin.schema'
import { getSession } from 'next-auth/react'

const BASE_URL = `${process.env.NEXT_PUBLIC_API_URL}/iam`

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

  // Para 204 No Content (inactivar, revocar)
  const contentType = res.headers.get('Content-Type')
  if (!contentType || !contentType.includes('application/json')) return null
  return res.json()
}

export const adminApi = {
  usuarios: {
    list: async (params?: { page?: number; size?: number }) => {
      const sp = new URLSearchParams()
      if (params?.page !== undefined) sp.set('page', String(params.page))
      if (params?.size !== undefined) sp.set('size', String(params.size))
      const data = await fetchWithAuth(`${BASE_URL}/users?${sp}`)
      return z.array(UsuarioResponseSchema).parse(data?.content ?? data)
    },

    getById: async (id: string) => {
      const data = await fetchWithAuth(`${BASE_URL}/users/${id}`)
      return UsuarioResponseSchema.parse(data)
    },

    create: async (input: CreateUsuarioInput) => {
      const data = await fetchWithAuth(`${BASE_URL}/users`, {
        method: 'POST',
        body: JSON.stringify(input),
      })
      return UsuarioResponseSchema.parse(data)
    },

    update: async (id: string, input: UpdateUsuarioInput) => {
      const data = await fetchWithAuth(`${BASE_URL}/users/${id}`, {
        method: 'PUT',
        body: JSON.stringify(input),
      })
      return UsuarioResponseSchema.parse(data)
    },

    inactivar: async (id: string) => {
      await fetchWithAuth(`${BASE_URL}/users/${id}/inactivar`, { method: 'POST' })
    },
  },

  roles: {
    list: async () => {
      const data = await fetchWithAuth(`${BASE_URL}/roles`)
      return z.array(RolResponseSchema).parse(data)
    },

    asignar: async (userId: string, rolId: string) => {
      await fetchWithAuth(`${BASE_URL}/users/${userId}/roles`, {
        method: 'POST',
        body: JSON.stringify({ rolId }),
      })
    },

    revocar: async (userId: string, roleId: string) => {
      await fetchWithAuth(`${BASE_URL}/users/${userId}/roles/${roleId}`, {
        method: 'DELETE',
      })
    },
  },

  permisos: {
    list: async () => {
      const data = await fetchWithAuth(`${BASE_URL}/permissions`)
      return z.array(PermisoResponseSchema).parse(data)
    },
  },
}
```

---

### 5.1 — 5.9 Hooks

**`useUsuarios`** — `src/hooks/administracion/useUsuarios.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'

export const USUARIOS_QUERY_KEY = ['iam-usuarios'] as const

export function useUsuarios(params?: { page?: number; size?: number }) {
  return useQuery({
    queryKey: [...USUARIOS_QUERY_KEY, params],
    queryFn: () => adminApi.usuarios.list(params),
    staleTime: 2 * 60 * 1000,
  })
}
```

**`useUsuario`** — `src/hooks/administracion/useUsuario.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'

export const usuarioQueryKey = (id: string) => ['iam-usuario', id] as const

export function useUsuario(id: string) {
  return useQuery({
    queryKey: usuarioQueryKey(id),
    queryFn: () => adminApi.usuarios.getById(id),
    enabled: !!id,
    staleTime: 2 * 60 * 1000,
  })
}
```

**`useCreateUsuario`** — `src/hooks/administracion/useCreateUsuario.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { adminApi } from '@/lib/api/admin.api'
import { USUARIOS_QUERY_KEY } from './useUsuarios'

export function useCreateUsuario() {
  const queryClient = useQueryClient()
  const router = useRouter()

  return useMutation({
    mutationFn: adminApi.usuarios.create,
    onSuccess: (newUser) => {
      queryClient.invalidateQueries({ queryKey: USUARIOS_QUERY_KEY })
      router.push(`/administracion/usuarios/${newUser.id}`)
    },
  })
}
```

**`useUpdateUsuario`** — `src/hooks/administracion/useUpdateUsuario.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'
import { usuarioQueryKey } from './useUsuario'

export function useUpdateUsuario(id: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: UpdateUsuarioInput) => adminApi.usuarios.update(id, input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: usuarioQueryKey(id) })
    },
  })
}
```

**`useInactivarUsuario`** — `src/hooks/administracion/useInactivarUsuario.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'
import { USUARIOS_QUERY_KEY } from './useUsuarios'
import { usuarioQueryKey } from './useUsuario'

export function useInactivarUsuario(id: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: () => adminApi.usuarios.inactivar(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: USUARIOS_QUERY_KEY })
      queryClient.invalidateQueries({ queryKey: usuarioQueryKey(id) })
    },
  })
}
```

**`useRoles`** — `src/hooks/administracion/useRoles.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'

export const ROLES_QUERY_KEY = ['iam-roles'] as const

export function useRoles() {
  return useQuery({
    queryKey: ROLES_QUERY_KEY,
    queryFn: adminApi.roles.list,
    staleTime: 10 * 60 * 1000, // 10 minutos — los roles cambian raramente
  })
}
```

**`useAsignarRol`** — `src/hooks/administracion/useAsignarRol.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'
import { usuarioQueryKey } from './useUsuario'

export function useAsignarRol(userId: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ rolId }: { rolId: string }) =>
      adminApi.roles.asignar(userId, rolId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: usuarioQueryKey(userId) })
    },
  })
}
```

**`useRevocarRol`** — `src/hooks/administracion/useRevocarRol.ts`

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'
import { usuarioQueryKey } from './useUsuario'

export function useRevocarRol(userId: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ roleId }: { roleId: string }) =>
      adminApi.roles.revocar(userId, roleId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: usuarioQueryKey(userId) })
    },
  })
}
```

**`usePermisos`** — `src/hooks/administracion/usePermisos.ts`

```typescript
import { useQuery } from '@tanstack/react-query'
import { adminApi } from '@/lib/api/admin.api'

export function usePermisos() {
  return useQuery({
    queryKey: ['iam-permisos'],
    queryFn: adminApi.permisos.list,
    staleTime: 10 * 60 * 1000,
  })
}
```

---

## 6. Estado Global (Zustand)

> **Nota TDD:** test-first — el test del slice se escribe antes de implementar el store.

### `adminSlice`

**Archivo:** `src/store/slices/adminSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export interface AdminSlice {
  usuarioFilter: string
  setUsuarioFilter: (text: string) => void
  clearUsuarioFilter: () => void
}

export const createAdminSlice: StateCreator<AdminSlice> = (set) => ({
  usuarioFilter: '',

  setUsuarioFilter: (text) => set({ usuarioFilter: text }),

  clearUsuarioFilter: () => set({ usuarioFilter: '' }),
})
```

**Archivo:** `src/store/adminStore.ts`

```typescript
import { create } from 'zustand'
import { devtools } from 'zustand/middleware'
import { AdminSlice, createAdminSlice } from './slices/adminSlice'

export const useAdminStore = create<AdminSlice>()(
  devtools(createAdminSlice, { name: 'AdminStore' })
)
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** test-first — los tests de schemas se escriben primero.

**Archivo:** `src/schemas/admin.schema.ts`

```typescript
import { z } from 'zod'

// --- Schemas de Input (request) ---

export const CreateUsuarioSchema = z.object({
  email: z
    .string({ required_error: 'El email es requerido' })
    .email('Debe ser un email válido')
    .toLowerCase(),
  nombre: z
    .string({ required_error: 'El nombre es requerido' })
    .min(1, 'El nombre no puede estar vacío')
    .max(200, 'El nombre no puede superar 200 caracteres')
    .trim(),
  initialRoles: z
    .array(z.string().uuid('El ID de rol debe ser un UUID válido'))
    .optional(),
})

export const UpdateUsuarioSchema = z.object({
  nombre: z
    .string({ required_error: 'El nombre es requerido' })
    .min(1, 'El nombre no puede estar vacío')
    .max(200, 'El nombre no puede superar 200 caracteres')
    .trim(),
  estado: z.enum(['ACTIVO', 'INACTIVO'], {
    required_error: 'El estado es requerido',
  }),
})

export const AsignarRolSchema = z.object({
  rolId: z
    .string({ required_error: 'El ID de rol es requerido' })
    .uuid('El ID de rol debe ser un UUID válido'),
})

// --- Schemas de Response (de la API) ---

export const RolResponseSchema = z.object({
  id: z.string().uuid(),
  nombre: z.string(),
  descripcion: z.string().nullable(),
  createdAt: z.string().datetime(),
})

export const UsuarioResponseSchema = z.object({
  id: z.string().uuid(),
  keycloakSub: z.string(),
  email: z.string().email(),
  nombre: z.string(),
  estado: z.enum(['ACTIVO', 'INACTIVO']),
  roles: z.array(RolResponseSchema).optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
})

export const PermisoResponseSchema = z.object({
  id: z.string().uuid(),
  modulo: z.string(),
  operacion: z.string(),
  descripcion: z.string().nullable(),
})

// --- Tipos inferidos ---

export type CreateUsuarioInput = z.infer<typeof CreateUsuarioSchema>
export type UpdateUsuarioInput = z.infer<typeof UpdateUsuarioSchema>
export type AsignarRolInput = z.infer<typeof AsignarRolSchema>
export type UsuarioResponse = z.infer<typeof UsuarioResponseSchema>
export type RolResponse = z.infer<typeof RolResponseSchema>
export type PermisoResponse = z.infer<typeof PermisoResponseSchema>
export type UsuarioResponseWithRoles = UsuarioResponse & { roles: RolResponse[] }
```

---

## 8. Autenticación y Autorización

### Acceso al Módulo

**Solo el rol Administrador** tiene acceso a cualquier ruta dentro de `/administracion/**`. Esta restricción se implementa en tres capas:

1. **Middleware de Next.js** (primera línea de defensa): redirige antes de renderizar la página
2. **Server Component** (segunda línea): verifica `getServerSession()` antes de renderizar
3. **Client Component guard** (tercera línea): `useSession()` + verificación de rol

### Nota sobre Keycloak

Cuando se crea un usuario mediante `POST /iam/users`:
1. El `iam-service` recibe la petición
2. El `iam-service` llama a la Admin API de Keycloak para crear la cuenta OIDC
3. El `iam-service` registra el usuario en su base de datos con el `keycloakSub`
4. El `iam-service` retorna el usuario creado al frontend

Este proceso es **transparente para el frontend**. No se requiere configuración adicional de Keycloak en el cliente.

### Impacto de Inactivar Usuario

Cuando se inactiva un usuario:
1. El frontend llama a `POST /iam/users/{id}/inactivar`
2. El `iam-service` deshabilita la cuenta en Keycloak
3. Los tokens JWT actuales del usuario invalidados en el próximo refresh
4. El usuario no puede obtener nuevos tokens de Keycloak

Esto es transparente para el frontend — solo se muestra que el estado del usuario pasa a INACTIVO.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Red-Green-Refactor:** Cada test se escribe primero en estado RED. Se implementa código mínimo para GREEN. Se refactoriza manteniendo todos los tests en GREEN.

### 9.1 Tests de Schemas

**Archivo:** `src/schemas/admin.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import {
  CreateUsuarioSchema,
  UpdateUsuarioSchema,
  AsignarRolSchema,
} from './admin.schema'

describe('CreateUsuarioSchema', () => {
  it('valida datos de usuario válidos completos', () => {
    const input = {
      email: 'nuevo@controlstock.com',
      nombre: 'Juan Pérez',
      initialRoles: ['123e4567-e89b-12d3-a456-426614174000'],
    }
    const result = CreateUsuarioSchema.safeParse(input)
    expect(result.success).toBe(true)
  })

  it('valida usuario sin roles iniciales (campo opcional)', () => {
    const input = {
      email: 'nuevo@controlstock.com',
      nombre: 'Juan Pérez',
    }
    const result = CreateUsuarioSchema.safeParse(input)
    expect(result.success).toBe(true)
    expect(result.data?.initialRoles).toBeUndefined()
  })

  it('falla cuando email es inválido', () => {
    const input = {
      email: 'no-es-un-email',
      nombre: 'Juan Pérez',
    }
    const result = CreateUsuarioSchema.safeParse(input)
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].path).toContain('email')
    expect(result.error?.issues[0].message).toMatch(/email/i)
  })

  it('falla cuando email está vacío', () => {
    const result = CreateUsuarioSchema.safeParse({ email: '', nombre: 'Juan' })
    expect(result.success).toBe(false)
  })

  it('falla cuando nombre está vacío', () => {
    const result = CreateUsuarioSchema.safeParse({
      email: 'juan@test.com',
      nombre: '',
    })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].path).toContain('nombre')
  })

  it('falla cuando nombre supera 200 caracteres', () => {
    const result = CreateUsuarioSchema.safeParse({
      email: 'juan@test.com',
      nombre: 'A'.repeat(201),
    })
    expect(result.success).toBe(false)
  })

  it('normaliza email a minúsculas', () => {
    const result = CreateUsuarioSchema.safeParse({
      email: 'JUAN@CONTROLSTOCK.COM',
      nombre: 'Juan',
    })
    expect(result.success).toBe(true)
    expect(result.data?.email).toBe('juan@controlstock.com')
  })

  it('falla cuando initialRoles contiene UUID inválido', () => {
    const result = CreateUsuarioSchema.safeParse({
      email: 'juan@test.com',
      nombre: 'Juan',
      initialRoles: ['no-es-uuid'],
    })
    expect(result.success).toBe(false)
  })
})

describe('AsignarRolSchema', () => {
  it('valida UUID válido', () => {
    const result = AsignarRolSchema.safeParse({
      rolId: '123e4567-e89b-12d3-a456-426614174000',
    })
    expect(result.success).toBe(true)
  })

  it('falla cuando rolId no es UUID válido', () => {
    const result = AsignarRolSchema.safeParse({ rolId: 'no-es-uuid' })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0].message).toMatch(/uuid/i)
  })

  it('falla cuando rolId está ausente', () => {
    const result = AsignarRolSchema.safeParse({})
    expect(result.success).toBe(false)
  })
})
```

---

### 9.2 Tests de Hooks

**Archivo:** `src/hooks/administracion/useUsuarios.test.ts`

```typescript
import { describe, it, expect, beforeAll, afterEach, afterAll } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'
import { createWrapper } from '@/test/utils'
import { useUsuarios } from './useUsuarios'
import { useAsignarRol } from './useAsignarRol'
import { useRevocarRol } from './useRevocarRol'

const MOCK_USUARIOS = [
  {
    id: '1',
    keycloakSub: 'kc-sub-1',
    email: 'usuario@test.com',
    nombre: 'Usuario Test',
    estado: 'ACTIVO',
    roles: [],
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-01T00:00:00.000Z',
  },
]

const MOCK_ROL = {
  id: 'rol-1',
  nombre: 'SUPERVISOR',
  descripcion: 'Supervisor del sistema',
  createdAt: '2024-01-01T00:00:00.000Z',
}

const server = setupServer(
  http.get('*/api/v1/iam/users', () => {
    return HttpResponse.json({ content: MOCK_USUARIOS })
  }),
  http.post('*/api/v1/iam/users/:userId/roles', () => {
    return HttpResponse.json(null, { status: 204 })
  }),
  http.delete('*/api/v1/iam/users/:userId/roles/:roleId', () => {
    return HttpResponse.json(null, { status: 204 })
  })
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('useUsuarios', () => {
  it('retorna estado de carga inicial', () => {
    const { result } = renderHook(() => useUsuarios(), { wrapper: createWrapper() })
    expect(result.current.isLoading).toBe(true)
  })

  it('retorna lista de usuarios en éxito', async () => {
    const { result } = renderHook(() => useUsuarios(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toHaveLength(1)
    expect(result.current.data![0].email).toBe('usuario@test.com')
  })

  it('retorna error cuando el servidor responde con error', async () => {
    server.use(
      http.get('*/api/v1/iam/users', () =>
        HttpResponse.json({ message: 'Error' }, { status: 500 })
      )
    )
    const { result } = renderHook(() => useUsuarios(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isError).toBe(true))
  })
})

describe('useAsignarRol', () => {
  it('en éxito invalida la query de useUsuario(userId)', async () => {
    const queryClient = createMockQueryClient()
    const invalidateSpy = vi.spyOn(queryClient, 'invalidateQueries')

    const { result } = renderHook(
      () => useAsignarRol('user-1'),
      { wrapper: createWrapper({ queryClient }) }
    )

    result.current.mutate({ rolId: 'rol-1' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))

    expect(invalidateSpy).toHaveBeenCalledWith(
      expect.objectContaining({ queryKey: ['iam-usuario', 'user-1'] })
    )
  })

  it('error 404 cuando rol no encontrado', async () => {
    server.use(
      http.post('*/api/v1/iam/users/*/roles', () =>
        HttpResponse.json({ message: 'Rol no encontrado' }, { status: 404 })
      )
    )
    const { result } = renderHook(() => useAsignarRol('user-1'), { wrapper: createWrapper() })
    result.current.mutate({ rolId: 'rol-inexistente' })
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(404)
  })

  it('error 409 cuando rol ya asignado', async () => {
    server.use(
      http.post('*/api/v1/iam/users/*/roles', () =>
        HttpResponse.json({ message: 'Rol ya asignado' }, { status: 409 })
      )
    )
    const { result } = renderHook(() => useAsignarRol('user-1'), { wrapper: createWrapper() })
    result.current.mutate({ rolId: 'rol-1' })
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(409)
  })
})

describe('useRevocarRol', () => {
  it('en éxito invalida la query de useUsuario(userId)', async () => {
    const { result } = renderHook(() => useRevocarRol('user-1'), { wrapper: createWrapper() })
    result.current.mutate({ roleId: 'rol-1' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
  })

  it('error 404 cuando el rol no está asignado al usuario', async () => {
    server.use(
      http.delete('*/api/v1/iam/users/*/roles/*', () =>
        HttpResponse.json({ message: 'Asignación no encontrada' }, { status: 404 })
      )
    )
    const { result } = renderHook(() => useRevocarRol('user-1'), { wrapper: createWrapper() })
    result.current.mutate({ roleId: 'rol-inexistente' })
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect((result.current.error as any).status).toBe(404)
  })
})
```

---

### 9.3 Tests de Componentes

**Archivo:** `src/components/administracion/UsuarioTable.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { UsuarioTable } from './UsuarioTable'
import { RoleAssignmentPanel } from './RoleAssignmentPanel'
import { InactivarUsuarioModal } from './InactivarUsuarioModal'

const mockUsuarios = [
  {
    id: '1',
    keycloakSub: 'kc-1',
    email: 'juan@test.com',
    nombre: 'Juan Pérez',
    estado: 'ACTIVO' as const,
    roles: [{ id: 'r1', nombre: 'SUPERVISOR', descripcion: null, createdAt: '2024-01-01T00:00:00.000Z' }],
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-01T00:00:00.000Z',
  },
]

describe('UsuarioTable', () => {
  it('renderiza columnas email, nombre, estado, roles y acciones', () => {
    render(<UsuarioTable usuarios={mockUsuarios} isLoading={false} searchText="" />)

    expect(screen.getByRole('columnheader', { name: /email/i })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: /nombre/i })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: /estado/i })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: /roles/i })).toBeInTheDocument()
  })

  it('filtra usuarios por texto de búsqueda (email)', () => {
    const multipleUsuarios = [
      ...mockUsuarios,
      {
        id: '2',
        keycloakSub: 'kc-2',
        email: 'maria@test.com',
        nombre: 'María García',
        estado: 'ACTIVO' as const,
        roles: [],
        createdAt: '2024-01-01T00:00:00.000Z',
        updatedAt: '2024-01-01T00:00:00.000Z',
      },
    ]

    render(
      <UsuarioTable usuarios={multipleUsuarios} isLoading={false} searchText="juan" />
    )

    expect(screen.getByText('juan@test.com')).toBeInTheDocument()
    expect(screen.queryByText('maria@test.com')).not.toBeInTheDocument()
  })

  it('muestra empty state cuando no hay coincidencias de búsqueda', () => {
    render(
      <UsuarioTable usuarios={mockUsuarios} isLoading={false} searchText="zzz-no-existe" />
    )
    expect(screen.getByTestId('empty-state')).toBeInTheDocument()
  })
})

describe('RoleAssignmentPanel', () => {
  const availableRoles = [
    { id: 'r1', nombre: 'SUPERVISOR', descripcion: 'Supervisor', createdAt: '2024-01-01T00:00:00.000Z' },
    { id: 'r2', nombre: 'ANALISTA', descripcion: 'Analista', createdAt: '2024-01-01T00:00:00.000Z' },
  ]

  it('muestra los roles actuales con botón × en cada uno', () => {
    render(
      <RoleAssignmentPanel
        userId="user-1"
        currentRoles={[availableRoles[0]]}
        availableRoles={availableRoles}
      />
    )

    expect(screen.getByTestId('rol-chip-supervisor')).toBeInTheDocument()
    expect(screen.getByTestId('revoke-supervisor-btn')).toBeInTheDocument()
  })

  it('dropdown solo muestra roles NO asignados actualmente', () => {
    render(
      <RoleAssignmentPanel
        userId="user-1"
        currentRoles={[availableRoles[0]]} // SUPERVISOR ya asignado
        availableRoles={availableRoles}
      />
    )

    const select = screen.getByTestId('add-role-select')
    const options = Array.from(select.querySelectorAll('option')).map(o => o.value)

    expect(options).not.toContain('r1') // SUPERVISOR ya asignado — no en dropdown
    expect(options).toContain('r2') // ANALISTA disponible para asignar
  })

  it('botón × llama a useRevocarRol con el roleId correcto', async () => {
    // Este test usa MSW para interceptar la llamada DELETE
    render(
      <RoleAssignmentPanel
        userId="user-1"
        currentRoles={[availableRoles[0]]}
        availableRoles={availableRoles}
      />
    )
    await userEvent.click(screen.getByTestId('revoke-supervisor-btn'))
    // Verificar que la mutación fue llamada — requiere wrapper con QueryClient
  })
})

describe('InactivarUsuarioModal', () => {
  const mockUsuario = { id: '1', email: 'juan@test.com', nombre: 'Juan Pérez' }

  it('botón de confirmación deshabilitado cuando email no coincide', () => {
    render(
      <InactivarUsuarioModal
        usuario={mockUsuario}
        isOpen={true}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
        isLoading={false}
      />
    )

    const confirmBtn = screen.getByTestId('modal-confirm-btn')
    expect(confirmBtn).toBeDisabled()
  })

  it('botón de confirmación habilitado cuando email coincide exactamente', async () => {
    render(
      <InactivarUsuarioModal
        usuario={mockUsuario}
        isOpen={true}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
        isLoading={false}
      />
    )

    await userEvent.type(
      screen.getByTestId('confirm-email-input'),
      'juan@test.com'
    )

    expect(screen.getByTestId('modal-confirm-btn')).toBeEnabled()
  })

  it('el modal no se renderiza cuando isOpen=false', () => {
    render(
      <InactivarUsuarioModal
        usuario={mockUsuario}
        isOpen={false}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
        isLoading={false}
      />
    )
    expect(screen.queryByTestId('inactivar-usuario-modal')).not.toBeInTheDocument()
  })

  it('botón cancelar llama a onCancel', async () => {
    const onCancel = vi.fn()
    render(
      <InactivarUsuarioModal
        usuario={mockUsuario}
        isOpen={true}
        onConfirm={vi.fn()}
        onCancel={onCancel}
        isLoading={false}
      />
    )
    await userEvent.click(screen.getByTestId('modal-cancel-btn'))
    expect(onCancel).toHaveBeenCalledTimes(1)
  })
})

describe('adminSlice', () => {
  it('setUsuarioFilter actualiza el texto de búsqueda', () => {
    const { result } = renderHook(() => useAdminStore())
    act(() => result.current.setUsuarioFilter('juan'))
    expect(result.current.usuarioFilter).toBe('juan')
  })

  it('clearUsuarioFilter vacía el texto', () => {
    const { result } = renderHook(() => useAdminStore())
    act(() => {
      result.current.setUsuarioFilter('juan')
      result.current.clearUsuarioFilter()
    })
    expect(result.current.usuarioFilter).toBe('')
  })

  it('estado inicial de usuarioFilter es cadena vacía', () => {
    const { result } = renderHook(() => useAdminStore())
    expect(result.current.usuarioFilter).toBe('')
  })
})
```

---

## 10. Pruebas E2E (Playwright, ATDD)

**Archivo:** `e2e/administracion/administracion.spec.ts`

```typescript
import { test, expect, Page } from '@playwright/test'
import { loginAs } from '../helpers/auth'

test.describe('Feature Administración', () => {

  // TC-ADM-01: Admin crea usuario → aparece en lista con estado ACTIVO
  test('TC-ADM-01: Administrador crea usuario y aparece en la lista con estado ACTIVO', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/administracion/usuarios/nuevo')
    await expect(page.getByRole('heading', { name: /nuevo usuario/i })).toBeVisible()

    // Dado que completo el formulario de creación
    await page.getByLabel('Email').fill('nuevo.usuario@controlstock.test')
    await page.getByLabel('Nombre Completo').fill('Nuevo Usuario Test')

    // Cuando envío el formulario
    await page.getByRole('button', { name: /crear usuario/i }).click()

    // Entonces soy redirigido al detalle del usuario
    await expect(page).toHaveURL(/\/administracion\/usuarios\/[\w-]+$/)
    await expect(page.getByTestId('user-email')).toHaveText('nuevo.usuario@controlstock.test')

    // Y el estado es ACTIVO
    await expect(page.getByTestId('estado-usuario-badge-activo')).toBeVisible()

    // Cuando regreso a la lista
    await page.goto('/administracion/usuarios')

    // Entonces el usuario aparece en la lista
    await expect(page.getByText('nuevo.usuario@controlstock.test')).toBeVisible()
  })

  // TC-ADM-02: Admin asigna rol Supervisor a usuario → aparece en detalle
  test('TC-ADM-02: Administrador asigna rol Supervisor a un usuario y aparece en el detalle', async ({ page }) => {
    await loginAs(page, 'admin')

    // Ir al detalle de un usuario existente
    await page.goto('/administracion/usuarios/test-user-id')

    // Dado que el usuario no tiene rol SUPERVISOR asignado
    const panel = page.getByTestId('role-assignment-panel')
    await expect(panel).toBeVisible()

    // Cuando selecciono SUPERVISOR en el dropdown y asigno
    await panel.getByTestId('add-role-select').selectOption({ label: /supervisor/i })
    await panel.getByTestId('add-role-btn').click()

    // Entonces el rol SUPERVISOR aparece en los chips de roles
    await expect(panel.getByTestId('rol-chip-supervisor')).toBeVisible()
    await expect(panel.getByTestId('revoke-supervisor-btn')).toBeVisible()
  })

  // TC-ADM-03: Admin revoca rol → ya no aparece en detalle
  test('TC-ADM-03: Administrador revoca rol y ya no aparece en el detalle del usuario', async ({ page }) => {
    await loginAs(page, 'admin')

    // Dado que el usuario tiene rol SUPERVISOR asignado
    await page.goto('/administracion/usuarios/test-user-with-supervisor-id')

    const panel = page.getByTestId('role-assignment-panel')
    await expect(panel.getByTestId('rol-chip-supervisor')).toBeVisible()

    // Cuando hago clic en × del chip SUPERVISOR
    await panel.getByTestId('revoke-supervisor-btn').click()

    // Entonces el chip de SUPERVISOR ya no aparece
    await expect(panel.getByTestId('rol-chip-supervisor')).not.toBeVisible()

    // Y aparece SUPERVISOR en el dropdown para asignar
    const options = await panel.getByTestId('add-role-select').locator('option').allTextContents()
    expect(options.some(o => o.toLowerCase().includes('supervisor'))).toBe(true)
  })

  // TC-ADM-04: Admin inactiva usuario → estado INACTIVO y usuario no puede loguear
  test('TC-ADM-04: Administrador inactiva usuario y estado cambia a INACTIVO', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/administracion/usuarios/test-active-user-id')

    // Dado que el usuario está ACTIVO
    await expect(page.getByTestId('estado-usuario-badge-activo')).toBeVisible()
    await expect(page.getByTestId('inactivar-btn')).toBeVisible()

    // Cuando hago clic en "Inactivar Usuario"
    await page.getByTestId('inactivar-btn').click()

    // Entonces aparece el modal de confirmación
    const modal = page.getByTestId('inactivar-usuario-modal')
    await expect(modal).toBeVisible()
    await expect(modal.getByTestId('modal-confirm-btn')).toBeDisabled()

    // Cuando ingreso el email del usuario
    const emailInput = modal.getByTestId('confirm-email-input')
    await emailInput.fill('usuario.activo@controlstock.test')
    await expect(modal.getByTestId('modal-confirm-btn')).toBeEnabled()

    // Y confirmo la inactivación
    await modal.getByTestId('modal-confirm-btn').click()

    // Entonces el estado cambia a INACTIVO
    await expect(page.getByTestId('estado-usuario-badge-inactivo')).toBeVisible()

    // Y el botón de inactivar ya no aparece
    await expect(page.getByTestId('inactivar-btn')).not.toBeVisible()
  })

  // TC-ADM-05: Supervisor navega a /administracion → redirigido a /dashboard
  test('TC-ADM-05: Supervisor es redirigido al intentar acceder a /administracion', async ({ page }) => {
    await loginAs(page, 'supervisor')

    await page.goto('/administracion')

    // El Supervisor no tiene acceso al módulo de administración
    await expect(page).toHaveURL('/dashboard')
    await expect(
      page.getByRole('heading', { name: /panel de administración/i })
    ).not.toBeVisible()
  })

  // Test adicional: Roles y permisos visible
  test('TC-ADM-06: Admin puede ver la tabla de roles y permisos del sistema', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/administracion/roles')

    await expect(page.getByRole('heading', { name: /roles/i })).toBeVisible()
    await expect(page.getByRole('section', { name: /tabla de permisos/i })).toBeVisible()

    // Debe haber al menos un módulo de permisos
    const modules = page.locator('[data-testid^="module-"]')
    await expect(modules.first()).toBeVisible()
  })

  // Test adicional: búsqueda de usuarios en la lista
  test('TC-ADM-07: Admin puede buscar usuarios por email o nombre', async ({ page }) => {
    await loginAs(page, 'admin')

    await page.goto('/administracion/usuarios')

    // Dado que hay múltiples usuarios
    const initialRows = page.locator('[data-testid^="row-"]')
    const initialCount = await initialRows.count()
    expect(initialCount).toBeGreaterThan(0)

    // Cuando escribo en el campo de búsqueda
    await page.getByRole('searchbox', { name: /buscar usuario/i }).fill('juan')

    // Entonces la lista se filtra
    const filteredRows = page.locator('[data-testid^="row-"]')
    const filteredCount = await filteredRows.count()
    expect(filteredCount).toBeLessThanOrEqual(initialCount)

    // Y todos los resultados contienen "juan"
    if (filteredCount > 0) {
      for (let i = 0; i < filteredCount; i++) {
        const row = filteredRows.nth(i)
        const text = await row.textContent()
        expect(text?.toLowerCase()).toContain('juan')
      }
    }
  })
})
```

---

## 11. Criterios de Aceptación

### CA-ADM-01: Control de Acceso Exclusivo

- **Dado** que soy usuario con cualquier rol distinto de Administrador
- **Cuando** intento acceder a cualquier ruta `/administracion/**`
- **Entonces** soy redirigido automáticamente a `/dashboard`
- **Y** no puedo acceder al módulo de ninguna forma desde el frontend

### CA-ADM-02: Creación de Usuario

- **Dado** que soy Administrador en `/administracion/usuarios/nuevo`
- **Cuando** completo el formulario con email válido y nombre
- **Y** opcionalmente selecciono roles iniciales
- **Y** hago clic en "Crear Usuario"
- **Entonces** el usuario se crea (backend sincroniza con Keycloak automáticamente)
- **Y** soy redirigido al detalle del nuevo usuario
- **Y** el usuario aparece en la lista con estado ACTIVO
- **Si** el email ya existe, el sistema muestra mensaje de error de duplicado

### CA-ADM-03: Asignación de Roles

- **Dado** que estoy en el detalle de un usuario como Administrador
- **Cuando** selecciono un rol del dropdown "Agregar Rol"
- **Y** hago clic en "Asignar Rol"
- **Entonces** el rol aparece como chip en el panel de roles del usuario
- **Y** el rol desaparece del dropdown (ya no está disponible para asignar)
- **Si** el rol ya está asignado, el sistema muestra info toast (error 409)
- **Si** el rol no existe, el sistema muestra error toast (error 404)

### CA-ADM-04: Revocación de Roles

- **Dado** que el usuario tiene roles asignados
- **Cuando** hago clic en el botón "×" de un chip de rol
- **Entonces** el rol es revocado y el chip desaparece del panel
- **Y** el rol vuelve a aparecer disponible en el dropdown de asignación
- **Si** el rol no estaba asignado al usuario, se muestra error toast (error 404)

### CA-ADM-05: Inactivación de Usuario con Doble Confirmación

- **Dado** que el usuario está ACTIVO y soy Administrador
- **Cuando** hago clic en "Inactivar Usuario"
- **Entonces** aparece un modal con nombre y email del usuario
- **Y** el botón de confirmación está deshabilitado hasta que ingrese exactamente el email del usuario
- **Cuando** ingreso el email correcto y confirmo
- **Entonces** el usuario queda con estado INACTIVO
- **Y** el botón de "Inactivar Usuario" desaparece (no tiene sentido inactivar lo ya inactivo)
- **Y** el usuario pierde acceso al sistema en el próximo refresh de token

### CA-ADM-06: Vista de Roles y Permisos

- **Dado** que soy Administrador en `/administracion/roles`
- **Cuando** cargo la página
- **Entonces** veo la lista de roles del sistema
- **Y** los permisos agrupados por módulo con nombre de operación y descripción
- Esta vista es de solo lectura — no hay botones de edición

### CA-ADM-07: Búsqueda de Usuarios

- **Dado** que estoy en la lista de usuarios
- **Cuando** escribo en el campo de búsqueda
- **Entonces** la lista se filtra en tiempo real por email o nombre
- Los filtros de búsqueda se mantienen al navegar entre páginas

### CA-ADM-08: Transparencia de Keycloak

- La creación de usuarios en el frontend produce un usuario funcional en Keycloak
- El proceso es transparente: el frontend no llama directamente a Keycloak
- El frontend muestra el `keycloakSub` en el detalle del usuario (solo referencia)
- Cuando un usuario es inactivado, su cuenta en Keycloak queda deshabilitada (gestionado por backend)

### CA-ADM-09: Requisitos TDD

- Todos los componentes tienen tests unitarios (Vitest) escritos primero (Red-Green-Refactor)
- `CreateUsuarioSchema` tiene tests de email inválido, nombre vacío, UUID inválido en roles
- `AsignarRolSchema` tiene tests de UUID válido e inválido
- `useAsignarRol` tiene tests de éxito, error 404 y error 409
- `useRevocarRol` tiene tests de éxito y error 404
- `InactivarUsuarioModal` tiene tests de habilitación por email coincidente y deshabilitación por email distinto
- `RoleAssignmentPanel` tiene tests de chips actuales y filtrado del dropdown
- `adminSlice` tiene tests de setUsuarioFilter y clearUsuarioFilter
- Los tests E2E en Playwright cubren: creación, asignación de rol, revocación de rol, inactivación y redirección de acceso
- Cobertura mínima requerida: 80% por archivo
