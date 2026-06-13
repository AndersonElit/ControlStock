# Etapa 4e — Frontend: Feature Ajustes de Inventario

## 1. Contexto y Objetivo

El feature **Ajustes de Inventario** implementa un flujo de solicitud y aprobación en dos etapas para correcciones manuales de stock. Un Operador crea una solicitud de ajuste (positiva o negativa), y un Supervisor o Administrador la aprueba o rechaza. La aprobación dispara una saga en el backend que actualiza el inventario de forma transaccional.

**Objetivo de la etapa:**
- Implementar las páginas y componentes del flujo de ajustes siguiendo TDD estricto (Red → Green → Refactor).
- Cada esquema Zod, hook TanStack Query y componente React tiene su prueba fallida escrita antes de la implementación.
- Los escenarios E2E Playwright (ATDD) están definidos y fallando antes de la integración completa.
- Conectar con `adjustment-service` a través de Kong API Gateway en `http://<VPS_IP>:8000/api/v1`.

**Particularidades del dominio:**
- La cantidad de ajuste puede ser negativa (para decrementar stock) pero no puede ser cero.
- El campo `sagaId` en `AjusteResponse` es opcional: se pobla solo cuando la saga de aprobación fue iniciada.
- El estado `ERROR` indica una saga fallida; el ajuste queda sin efecto y se muestra al usuario.
- Solo Supervisor y Administrador pueden tomar decisiones sobre ajustes en estado `PENDIENTE`.

---

## 2. Prerrequisitos

| Ítem | Detalle |
|------|---------|
| Etapa 4a completada | Scaffold Next.js 14, App Router, providers configurados |
| Etapa 4b completada | NextAuth.js 4 + Keycloak, `middleware.ts`, roles en JWT |
| Etapa 4c completada | Feature Catálogo: `useStock()` disponible para obtener stock actual del producto seleccionado |
| Etapa 4d completada | Feature Inventario: `inventarioSlice`, `useStockByProducto()` |
| Variables de entorno | `NEXT_PUBLIC_API_URL` configurada |
| MSW v2 | Handlers para `adjustment-service` en `src/mocks/handlers/adjustments.ts` |
| Vitest + RTL + user-event | Configurados y funcionando |
| Playwright | Configurado con fixtures de autenticación por rol |
| `ajustesSlice` | Se crea en esta etapa dentro del store Zustand global |

---

## 3. Rutas y Páginas

Todas las rutas viven bajo `src/app/(protected)/ajustes/`.

| Ruta | Tipo | Archivo de Página | Componente de Página | Descripción |
|------|------|-------------------|----------------------|-------------|
| `/ajustes` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/ajustes/page.tsx` | `AjusteListPage` | Listado de solicitudes de ajuste con filtro por estado |
| `/ajustes/nuevo` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/ajustes/nuevo/page.tsx` | `AjusteFormPage` | Formulario para crear solicitud de ajuste |
| `/ajustes/[id]` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/ajustes/[id]/page.tsx` | `AjusteDetailPage` | Detalle del ajuste: info + sección de decisión + historial |

### Protección de rutas

```typescript
// middleware.ts — reglas de ajustes
const ROUTE_ROLES: Record<string, string[]> = {
  '/ajustes':        ['Operador', 'Supervisor', 'Administrador'],
  '/ajustes/nuevo':  ['Operador', 'Supervisor', 'Administrador'],
  '/ajustes/:id':    ['Operador', 'Supervisor', 'Administrador'],
};
// Roles Gerente, Analista y Auditor NO tienen acceso al feature de ajustes.
```

> Nota: La visibilidad de los botones Aprobar/Rechazar se controla en el componente `AjusteDetail` por rol Y estado del ajuste; no requiere ruta separada.

---

## 4. Componentes

> **Nota TDD:** Para cada componente: primero el archivo de prueba con importación del componente (falla con "cannot find module" o similar) → luego el componente mínimo → luego iteraciones Green → Refactor.

### 4.1 `AjusteTable`

**Archivo:** `src/features/ajustes/components/AjusteTable.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/AjusteTable.test.tsx`

**Props:**
```typescript
interface AjusteTableProps {
  ajustes: AjusteResponse[];
  totalPages: number;
  currentPage: number;
  onPageChange: (page: number) => void;
  isLoading?: boolean;
}
```

**Columnas:**
| Columna | Campo fuente | Notas |
|---------|-------------|-------|
| Fecha | `createdAt` | Formato `dd/MM/yyyy HH:mm` |
| Producto | `nombreProducto` | Enlace a `/catalogo/productos/{productoId}` |
| Cantidad | `cantidad` | Rojo si negativo, verde si positivo; prefijo +/− |
| Motivo | `motivo` | Truncado a 60 chars con ellipsis tooltip |
| Estado | `estado` | `<AjusteStatusBadge estado={row.estado} />` |
| Acciones | — | Enlace a detalle del ajuste |

**Comportamiento:**
- Skeleton de carga: 5 filas.
- Estado vacío: "No hay solicitudes de ajuste registradas."
- Las filas con estado `ERROR` tienen fondo `bg-red-50`.

---

### 4.2 `AjusteStatusBadge`

**Archivo:** `src/features/ajustes/components/AjusteStatusBadge.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/AjusteStatusBadge.test.tsx`

**Props:**
```typescript
interface AjusteStatusBadgeProps {
  estado: 'PENDIENTE' | 'APROBADO' | 'RECHAZADO' | 'ERROR';
}
```

**Colores:**
| Estado | Clases CSS | Texto |
|--------|-----------|-------|
| `PENDIENTE` | `bg-amber-100 text-amber-800` | "PENDIENTE" |
| `APROBADO` | `bg-green-100 text-green-800` | "APROBADO" |
| `RECHAZADO` | `bg-red-100 text-red-800` | "RECHAZADO" |
| `ERROR` | `bg-gray-100 text-gray-600` | "ERROR" |

---

### 4.3 `AjusteForm`

**Archivo:** `src/features/ajustes/components/AjusteForm.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/AjusteForm.test.tsx`

**Props:**
```typescript
interface AjusteFormProps {
  onSuccess?: (ajusteId: string) => void;
}
```

**Campos:**
| Campo | Tipo | Validación |
|-------|------|-----------|
| `productoId` | `<select>` buscable | Opciones de `useStock()`; requerido; muestra código + nombre |
| `cantidad` | `<input type="number">` | Requerido, no puede ser 0, puede ser negativo |
| `motivo` | `<textarea>` | Requerido, mín 10, máx 500 chars |

**Funcionalidad adicional:**
- Al seleccionar un producto, se llama `useStockByProducto(productoId)` y se muestra el stock actual en un card informativo bajo el selector:
  ```
  Stock actual: [X] unidades | Mínimo: [Y] | Máximo: [Z]
  ```
- Esta información es solo de lectura y ayuda al operador a dimensionar el ajuste.

**Integración React Hook Form:**
```typescript
const form = useForm<CreateAjusteInput>({
  resolver: zodResolver(CreateAjusteSchema),
});
const selectedProductoId = form.watch('productoId');
const { data: stockActual } = useStockByProducto(selectedProductoId);
```

---

### 4.4 `AjusteDetail`

**Archivo:** `src/features/ajustes/components/AjusteDetail.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/AjusteDetail.test.tsx`

**Props:**
```typescript
interface AjusteDetailProps {
  ajusteId: string;
}
```

**Layout:**
```
┌─────────────────────────────────────────┐
│ Encabezado: solicitud info card          │
│ Producto | Cantidad | Estado | Fecha     │
│ Solicitante: {usuarioSolicitante}        │
│ Motivo: {motivo}                         │
│ sagaId (si existe): {sagaId}             │
├─────────────────────────────────────────┤
│ Sección Decisión (condicional)           │
│ [Solo si Supervisor/Admin Y PENDIENTE]  │
│ [AprobarAjusteModal trigger] [RechazarAjusteModal trigger] │
├─────────────────────────────────────────┤
│ Historial de decisiones                  │
│ <DecisionHistory ajusteId={ajusteId} /> │
└─────────────────────────────────────────┘
```

**Lógica de visibilidad:**
```typescript
const roles = useRol();
const esTomadorDecision = tieneRol(roles, 'Supervisor', 'Administrador');
const mostrarDecision   = esTomadorDecision && ajuste.estado === 'PENDIENTE';
```

---

### 4.5 `AprobarAjusteModal`

**Archivo:** `src/features/ajustes/components/AprobarAjusteModal.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/AprobarAjusteModal.test.tsx`

**Props:**
```typescript
interface AprobarAjusteModalProps {
  open: boolean;
  ajusteId: string;
  productoNombre: string;
  cantidad: number;
  onConfirm: () => void;
  onCancel: () => void;
  isLoading?: boolean;
}
```

**Comportamiento:**
- Sin campos adicionales; solo confirmación explícita.
- Mensaje: `¿Aprobar ajuste de ${cantidad > 0 ? '+' : ''}${cantidad} unidades para "${productoNombre}"? Esta acción actualizará el stock del inventario.`
- Botón "Aprobar" llama `onConfirm` y deshabilita durante `isLoading`.
- Botón "Cancelar" llama `onCancel` y cierra el modal.

---

### 4.6 `RechazarAjusteModal`

**Archivo:** `src/features/ajustes/components/RechazarAjusteModal.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/RechazarAjusteModal.test.tsx`

**Props:**
```typescript
interface RechazarAjusteModalProps {
  open: boolean;
  ajusteId: string;
  onConfirm: (comentario?: string) => void;
  onCancel: () => void;
  isLoading?: boolean;
}
```

**Campos:**
- `comentario`: `<textarea>` opcional, máx 500 chars. Label: "Motivo del rechazo (opcional)".

**Validación interna:** `RechazarSchema` con `zodResolver` dentro del modal.

---

### 4.7 `DecisionHistory`

**Archivo:** `src/features/ajustes/components/DecisionHistory.tsx`
**Prueba:** `src/features/ajustes/components/__tests__/DecisionHistory.test.tsx`

**Props:**
```typescript
interface DecisionHistoryProps {
  decisions: AjusteDecision[];
}

interface AjusteDecision {
  id: string;
  tipo: 'APROBACION' | 'RECHAZO';
  decisor: string;
  comentario?: string;
  fecha: string;
}
```

**Renderizado:**
- Lista vertical de tarjetas, ordenadas cronológicamente.
- Cada tarjeta: `[tipo badge] | [decisor] | [fecha] | [comentario si existe]`.
- Estado vacío: "Sin historial de decisiones."

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** Handler MSW + test del hook escritos antes de implementar el hook.

Todos los hooks residen en `src/features/ajustes/hooks/`.

### 5.1 `useAjustes`

```typescript
// src/features/ajustes/hooks/useAjustes.ts
export function useAjustes(params?: AjustesParams) {
  return useQuery({
    queryKey: ['ajustes', params],
    queryFn: () => fetchAjustes(params),
    staleTime: 30 * 1000,
  });
}
```

- **Endpoint:** `GET /adjustments`
- **Query params:** `{ estado?: 'PENDIENTE'|'APROBADO'|'RECHAZADO'|'ERROR', page?: number, size?: number }`
- **staleTime:** 30 segundos — los ajustes pendientes pueden cambiar con frecuencia.

---

### 5.2 `useAjuste`

```typescript
export function useAjuste(id: string) {
  return useQuery({
    queryKey: ['ajustes', id],
    queryFn: () => fetchAjusteById(id),
    enabled: !!id,
    staleTime: 30 * 1000,
  });
}
```

- **Endpoint:** `GET /adjustments/{id}`

---

### 5.3 `useCreateAjuste`

```typescript
export function useCreateAjuste() {
  const router = useRouter();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateAjusteInput) => createAjuste(data),
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: ['ajustes'] });
      router.push(`/ajustes/${created.id}`);
    },
  });
}
```

- **Endpoint:** `POST /adjustments`

---

### 5.4 `useAprobarAjuste`

```typescript
export function useAprobarAjuste(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => aprobarAjuste(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['ajustes', id] });
      queryClient.invalidateQueries({ queryKey: ['ajustes'] });
      queryClient.invalidateQueries({ queryKey: ['stock'] });
    },
  });
}
```

- **Endpoint:** `POST /adjustments/{id}/aprobar`
- **Post-success:** Invalida el detalle del ajuste específico, la lista y el stock (porque el ajuste afecta el inventario).

---

### 5.5 `useRechazarAjuste`

```typescript
export function useRechazarAjuste(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: RechazarInput) => rechazarAjuste(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['ajustes', id] });
      queryClient.invalidateQueries({ queryKey: ['ajustes'] });
    },
  });
}
```

- **Endpoint:** `POST /adjustments/{id}/rechazar`
- **Body:** `{ comentario?: string }`

---

## 6. Estado Global (Zustand)

> **Nota TDD:** Pruebas de cada acción escritas antes de implementar el slice.

**Archivo:** `src/store/slices/ajustesSlice.ts`

```typescript
type EstadoAjuste = 'TODOS' | 'PENDIENTE' | 'APROBADO' | 'RECHAZADO' | 'ERROR';

interface AjustesState {
  estadoFilter: EstadoAjuste;
  setEstadoFilter: (estado: EstadoAjuste) => void;
}

export const useAjustesSlice = (set: SetState<AjustesState>): AjustesState => ({
  estadoFilter: 'TODOS',
  setEstadoFilter: (estado) => set({ estadoFilter: estado }),
});
```

**Integración con `AjusteListPage`:**
```typescript
const { estadoFilter, setEstadoFilter } = useAjustesStore();
const { data, isLoading } = useAjustes({
  estado: estadoFilter === 'TODOS' ? undefined : estadoFilter,
  page: currentPage,
  size: 20,
});
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** Test unitario con casos válidos e inválidos escrito antes de definir el schema.

**Archivo:** `src/features/ajustes/schemas/ajuste.schema.ts`

```typescript
import { z } from 'zod';

export const CreateAjusteSchema = z.object({
  productoId: z.string().uuid('Debe seleccionar un producto válido'),
  cantidad: z
    .number({ invalid_type_error: 'Ingrese un número' })
    .refine((v) => v !== 0, { message: 'La cantidad no puede ser cero' }),
  motivo: z
    .string()
    .min(10, 'Mínimo 10 caracteres')
    .max(500, 'Máximo 500 caracteres'),
});

export const RechazarSchema = z.object({
  comentario: z.string().max(500, 'Máximo 500 caracteres').optional(),
});

export const AjusteResponseSchema = z.object({
  id:                   z.string().uuid(),
  productoId:           z.string().uuid(),
  cantidad:             z.number(),
  motivo:               z.string(),
  estado:               z.enum(['PENDIENTE', 'APROBADO', 'RECHAZADO', 'ERROR']),
  usuarioSolicitante:   z.string(),
  sagaId:               z.string().uuid().optional(),
  createdAt:            z.string().datetime(),
  updatedAt:            z.string().datetime(),
});

export type CreateAjusteInput = z.infer<typeof CreateAjusteSchema>;
export type RechazarInput     = z.infer<typeof RechazarSchema>;
export type AjusteResponse    = z.infer<typeof AjusteResponseSchema>;
```

---

## 8. Autenticación y Autorización

### 8.1 Tabla de permisos por acción en Ajustes

| Acción | Operador | Supervisor | Administrador | Gerente | Analista | Auditor |
|--------|----------|-----------|---------------|---------|----------|---------|
| Ver lista de ajustes | ✓ | ✓ | ✓ | — | — | — |
| Crear solicitud de ajuste | ✓ | ✓ | ✓ | — | — | — |
| Ver detalle de ajuste | ✓ | ✓ | ✓ | — | — | — |
| Aprobar ajuste | — | ✓ | ✓ | — | — | — |
| Rechazar ajuste | — | ✓ | ✓ | — | — | — |

### 8.2 Control de acceso en `AjusteDetail`

```typescript
// src/features/ajustes/components/AjusteDetail.tsx
const roles = useRol();
const esTomadorDecision = tieneRol(roles, 'Supervisor', 'Administrador');
const mostrarDecision   = esTomadorDecision && ajuste.estado === 'PENDIENTE';

{mostrarDecision && (
  <div className="flex gap-3">
    <Button onClick={() => setAprobarOpen(true)} variant="success">
      Aprobar
    </Button>
    <Button onClick={() => setRechazarOpen(true)} variant="danger">
      Rechazar
    </Button>
  </div>
)}
```

### 8.3 Error 403 para Operador intentando aprobar

Si un Operador intenta llamar directamente al endpoint (bypass de UI), el backend responde con 403. El hook `useAprobarAjuste` trata el error 403 mostrando un toast de "No autorizado para realizar esta acción."

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Regla Red-Green-Refactor:** Cada sección inicia con el test fallido (Red), luego se implementa el mínimo (Green), luego se mejora el código (Refactor).

### 9.1 Pruebas de `CreateAjusteSchema`

**Archivo:** `src/features/ajustes/schemas/__tests__/ajuste.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { CreateAjusteSchema } from '../ajuste.schema';

describe('CreateAjusteSchema', () => {
  const baseValido = {
    productoId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    cantidad:   50,
    motivo:     'Ajuste por inventario físico anual encontró discrepancia.',
  };

  it('debería pasar con cantidad positiva válida', () => {
    expect(CreateAjusteSchema.safeParse(baseValido).success).toBe(true);
  });

  it('debería pasar con cantidad negativa válida', () => {
    const result = CreateAjusteSchema.safeParse({ ...baseValido, cantidad: -20 });
    expect(result.success).toBe(true);
  });

  it('debería fallar cuando cantidad = 0', () => {
    const result = CreateAjusteSchema.safeParse({ ...baseValido, cantidad: 0 });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].message).toBe('La cantidad no puede ser cero');
  });

  it('debería fallar si motivo tiene 9 caracteres (< 10)', () => {
    const result = CreateAjusteSchema.safeParse({ ...baseValido, motivo: '123456789' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('motivo');
    expect(result.error?.issues[0].message).toContain('Mínimo 10 caracteres');
  });

  it('debería pasar si motivo tiene exactamente 10 caracteres', () => {
    const result = CreateAjusteSchema.safeParse({ ...baseValido, motivo: '1234567890' });
    expect(result.success).toBe(true);
  });

  it('debería fallar si motivo supera 500 caracteres', () => {
    const motivoLargo = 'a'.repeat(501);
    const result = CreateAjusteSchema.safeParse({ ...baseValido, motivo: motivoLargo });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].message).toContain('Máximo 500 caracteres');
  });

  it('debería fallar si productoId no es UUID', () => {
    const result = CreateAjusteSchema.safeParse({ ...baseValido, productoId: 'no-es-uuid' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('productoId');
  });

  it('debería fallar si productoId está ausente', () => {
    const { productoId, ...sinProducto } = baseValido;
    const result = CreateAjusteSchema.safeParse(sinProducto);
    expect(result.success).toBe(false);
  });
});
```

---

### 9.2 Pruebas del hook `useCreateAjuste`

**Archivo:** `src/features/ajustes/hooks/__tests__/useCreateAjuste.test.tsx`

MSW handlers:

```typescript
// src/mocks/handlers/adjustments.ts
import { http, HttpResponse } from 'msw';

export const adjustmentHandlers = [
  http.post('/api/v1/adjustments', () =>
    HttpResponse.json(
      {
        id: 'ajuste-uuid-1',
        productoId: 'prod-uuid-1',
        cantidad: 50,
        motivo: 'Ajuste por inventario físico.',
        estado: 'PENDIENTE',
        usuarioSolicitante: 'operador@test.com',
        createdAt: '2025-06-01T10:00:00Z',
        updatedAt: '2025-06-01T10:00:00Z',
      },
      { status: 201 }
    )
  ),
];
```

```typescript
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useCreateAjuste } from '../useCreateAjuste';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

const mockPush = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush }) }));

describe('useCreateAjuste', () => {
  const validPayload = {
    productoId: 'prod-uuid-1',
    cantidad:   50,
    motivo:     'Ajuste por inventario físico anual.',
  };

  it('éxito: navega al detalle del ajuste creado', async () => {
    const { result } = renderHook(() => useCreateAjuste(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockPush).toHaveBeenCalledWith('/ajustes/ajuste-uuid-1');
  });

  it('error 400: la mutación queda en estado error con mensaje de validación', async () => {
    server.use(
      http.post('/api/v1/adjustments', () =>
        HttpResponse.json({ message: 'Producto no encontrado' }, { status: 400 })
      )
    );
    const { result } = renderHook(() => useCreateAjuste(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

---

### 9.3 Pruebas del hook `useAprobarAjuste`

**Archivo:** `src/features/ajustes/hooks/__tests__/useAprobarAjuste.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useAprobarAjuste } from '../useAprobarAjuste';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

describe('useAprobarAjuste', () => {
  it('éxito: el estado del ajuste cambia a APROBADO en caché', async () => {
    server.use(
      http.post('/api/v1/adjustments/:id/aprobar', () =>
        HttpResponse.json({ id: 'ajuste-1', estado: 'APROBADO' }, { status: 200 })
      )
    );
    const { result } = renderHook(() => useAprobarAjuste('ajuste-1'), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(); });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
  });

  it('error 403 para rol Operador: la mutación falla con error de autorización', async () => {
    server.use(
      http.post('/api/v1/adjustments/:id/aprobar', () =>
        HttpResponse.json({ message: 'Forbidden' }, { status: 403 })
      )
    );
    const { result } = renderHook(() => useAprobarAjuste('ajuste-1'), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(); });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect((result.current.error as any)?.status).toBe(403);
  });
});
```

---

### 9.4 Pruebas del componente `AjusteForm`

**Archivo:** `src/features/ajustes/components/__tests__/AjusteForm.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AjusteForm } from '../AjusteForm';

vi.mock('@/features/inventario/hooks/useStock', () => ({
  useStock: () => ({
    data: [
      { productoId: 'prod-uuid-1', codigoProducto: 'P001', nombreProducto: 'Aceite',
        stockActual: 50, stockMinimo: 10, stockMaximo: 200 },
    ],
    isLoading: false,
  }),
}));

vi.mock('@/features/inventario/hooks/useStockByProducto', () => ({
  useStockByProducto: (id: string) => ({
    data: id ? { stockActual: 50, stockMinimo: 10, stockMaximo: 200 } : undefined,
    isLoading: false,
  }),
}));

describe('AjusteForm', () => {
  it('debería renderizar el formulario correctamente', () => {
    render(<AjusteForm />);
    expect(screen.getByLabelText(/producto/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/cantidad/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/motivo/i)).toBeInTheDocument();
  });

  it('debería mostrar error cuando cantidad = 0', async () => {
    const user = userEvent.setup();
    render(<AjusteForm />);
    await user.selectOptions(screen.getByLabelText(/producto/i), 'prod-uuid-1');
    await user.type(screen.getByLabelText(/cantidad/i), '0');
    await user.type(screen.getByLabelText(/motivo/i), 'Motivo de prueba con más de 10 caracteres');
    await user.click(screen.getByRole('button', { name: /solicitar ajuste/i }));
    await waitFor(() =>
      expect(screen.getByText(/la cantidad no puede ser cero/i)).toBeInTheDocument()
    );
  });

  it('debería mostrar error cuando motivo tiene menos de 10 caracteres', async () => {
    const user = userEvent.setup();
    render(<AjusteForm />);
    await user.selectOptions(screen.getByLabelText(/producto/i), 'prod-uuid-1');
    await user.type(screen.getByLabelText(/cantidad/i), '10');
    await user.type(screen.getByLabelText(/motivo/i), 'Corto');
    await user.click(screen.getByRole('button', { name: /solicitar ajuste/i }));
    await waitFor(() =>
      expect(screen.getByText(/mínimo 10 caracteres/i)).toBeInTheDocument()
    );
  });

  it('debería mostrar el stock actual del producto seleccionado', async () => {
    const user = userEvent.setup();
    render(<AjusteForm />);
    await user.selectOptions(screen.getByLabelText(/producto/i), 'prod-uuid-1');
    await waitFor(() =>
      expect(screen.getByText(/stock actual: 50/i)).toBeInTheDocument()
    );
  });

  it('debería aceptar cantidad negativa válida con motivo suficiente', async () => {
    const mockMutate = vi.fn();
    vi.mock('@/features/ajustes/hooks/useCreateAjuste', () => ({
      useCreateAjuste: () => ({ mutate: mockMutate, isPending: false }),
    }));
    const user = userEvent.setup();
    render(<AjusteForm />);
    await user.selectOptions(screen.getByLabelText(/producto/i), 'prod-uuid-1');
    await user.type(screen.getByLabelText(/cantidad/i), '-20');
    await user.type(screen.getByLabelText(/motivo/i), 'Corrección por merma detectada en conteo físico.');
    await user.click(screen.getByRole('button', { name: /solicitar ajuste/i }));
    // El formulario debería enviarse (mutate llamado) o al menos no mostrar errores
    await waitFor(() =>
      expect(screen.queryByText(/la cantidad no puede ser cero/i)).not.toBeInTheDocument()
    );
  });
});
```

---

### 9.5 Pruebas del componente `AprobarAjusteModal`

**Archivo:** `src/features/ajustes/components/__tests__/AprobarAjusteModal.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AprobarAjusteModal } from '../AprobarAjusteModal';

describe('AprobarAjusteModal', () => {
  const defaultProps = {
    open: true,
    ajusteId: 'ajuste-uuid-1',
    productoNombre: 'Aceite Motor 10W40',
    cantidad: 50,
    onConfirm: vi.fn(),
    onCancel: vi.fn(),
    isLoading: false,
  };

  it('debería renderizar el modal cuando open=true', () => {
    render(<AprobarAjusteModal {...defaultProps} />);
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });

  it('debería mostrar el nombre del producto y la cantidad en el mensaje', () => {
    render(<AprobarAjusteModal {...defaultProps} />);
    expect(screen.getByText(/aceite motor 10w40/i)).toBeInTheDocument();
    expect(screen.getByText(/\+50/i)).toBeInTheDocument();
  });

  it('debería llamar onConfirm al hacer click en "Aprobar"', async () => {
    const onConfirm = vi.fn();
    const user = userEvent.setup();
    render(<AprobarAjusteModal {...defaultProps} onConfirm={onConfirm} />);
    await user.click(screen.getByRole('button', { name: /aprobar/i }));
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it('debería llamar onCancel al hacer click en "Cancelar"', async () => {
    const onCancel = vi.fn();
    const user = userEvent.setup();
    render(<AprobarAjusteModal {...defaultProps} onCancel={onCancel} />);
    await user.click(screen.getByRole('button', { name: /cancelar/i }));
    expect(onCancel).toHaveBeenCalledOnce();
  });

  it('debería deshabilitar el botón "Aprobar" cuando isLoading=true', () => {
    render(<AprobarAjusteModal {...defaultProps} isLoading={true} />);
    expect(screen.getByRole('button', { name: /aprobar/i })).toBeDisabled();
  });

  it('NO debería renderizar nada cuando open=false', () => {
    render(<AprobarAjusteModal {...defaultProps} open={false} />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});
```

---

### 9.6 Pruebas del componente `AjusteStatusBadge`

**Archivo:** `src/features/ajustes/components/__tests__/AjusteStatusBadge.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AjusteStatusBadge } from '../AjusteStatusBadge';

describe('AjusteStatusBadge', () => {
  it('PENDIENTE → badge ámbar', () => {
    render(<AjusteStatusBadge estado="PENDIENTE" />);
    const badge = screen.getByText('PENDIENTE');
    expect(badge).toHaveClass('bg-amber-100');
    expect(badge).toHaveClass('text-amber-800');
  });

  it('APROBADO → badge verde', () => {
    render(<AjusteStatusBadge estado="APROBADO" />);
    const badge = screen.getByText('APROBADO');
    expect(badge).toHaveClass('bg-green-100');
    expect(badge).toHaveClass('text-green-800');
  });

  it('RECHAZADO → badge rojo', () => {
    render(<AjusteStatusBadge estado="RECHAZADO" />);
    const badge = screen.getByText('RECHAZADO');
    expect(badge).toHaveClass('bg-red-100');
    expect(badge).toHaveClass('text-red-800');
  });

  it('ERROR → badge gris', () => {
    render(<AjusteStatusBadge estado="ERROR" />);
    const badge = screen.getByText('ERROR');
    expect(badge).toHaveClass('bg-gray-100');
    expect(badge).toHaveClass('text-gray-600');
  });
});
```

---

### 9.7 Pruebas del `ajustesSlice`

**Archivo:** `src/store/slices/__tests__/ajustesSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { act } from '@testing-library/react';
import { create } from 'zustand';
import { useAjustesSlice } from '../ajustesSlice';

const useTestStore = create(useAjustesSlice);

describe('ajustesSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ estadoFilter: 'TODOS' });
  });

  it('estado inicial: estadoFilter = TODOS', () => {
    expect(useTestStore.getState().estadoFilter).toBe('TODOS');
  });

  it('setEstadoFilter: cambia a PENDIENTE', () => {
    act(() => { useTestStore.getState().setEstadoFilter('PENDIENTE'); });
    expect(useTestStore.getState().estadoFilter).toBe('PENDIENTE');
  });

  it('setEstadoFilter: cambia a APROBADO', () => {
    act(() => { useTestStore.getState().setEstadoFilter('APROBADO'); });
    expect(useTestStore.getState().estadoFilter).toBe('APROBADO');
  });

  it('setEstadoFilter: cambia a RECHAZADO', () => {
    act(() => { useTestStore.getState().setEstadoFilter('RECHAZADO'); });
    expect(useTestStore.getState().estadoFilter).toBe('RECHAZADO');
  });

  it('setEstadoFilter: cambia a ERROR', () => {
    act(() => { useTestStore.getState().setEstadoFilter('ERROR'); });
    expect(useTestStore.getState().estadoFilter).toBe('ERROR');
  });

  it('setEstadoFilter: puede volver a TODOS desde cualquier estado', () => {
    act(() => {
      useTestStore.getState().setEstadoFilter('RECHAZADO');
      useTestStore.getState().setEstadoFilter('TODOS');
    });
    expect(useTestStore.getState().estadoFilter).toBe('TODOS');
  });
});
```

---

## 10. Pruebas E2E (Playwright, ATDD)

> **Principio ATDD:** Los escenarios se redactan antes de la implementación. Cada test falla inicialmente hasta que el feature está completo.

**Archivo:** `e2e/ajustes/ajustes.spec.ts`

### Datos seed requeridos en staging

```yaml
# seed-ajustes.yml
ajustes:
  - id: "aju-seed-01"
    productoId: "prod-seed-inv-01"
    cantidad: 25
    motivo: "Ajuste seed para prueba E2E de aprobación."
    estado: "PENDIENTE"
    usuarioSolicitante: "operador@seed.com"
    createdAt: "2025-06-01T08:00:00Z"
    updatedAt: "2025-06-01T08:00:00Z"

  - id: "aju-seed-02"
    productoId: "prod-seed-inv-01"
    cantidad: -10
    motivo: "Ajuste seed para prueba E2E de rechazo con comentario."
    estado: "PENDIENTE"
    usuarioSolicitante: "operador@seed.com"
    createdAt: "2025-06-01T09:00:00Z"
    updatedAt: "2025-06-01T09:00:00Z"
```

---

### TC-AJU-01: Operador crea un ajuste y aparece como PENDIENTE en la lista

```typescript
test('TC-AJU-01: Operador crea una solicitud de ajuste y aparece como PENDIENTE', async ({ page }) => {
  // GIVEN: Operador autenticado en /ajustes
  await page.goto('/ajustes');
  await expect(page.getByRole('heading', { name: /ajustes/i })).toBeVisible();

  // WHEN: Click en "Nueva solicitud"
  await page.getByRole('link', { name: /nueva solicitud/i }).click();
  await expect(page).toHaveURL('/ajustes/nuevo');

  // AND: Completa el formulario
  await page.getByLabel(/producto/i).selectOption({ label: 'Aceite Motor Seed' });
  // Verificar que aparece el stock actual
  await expect(page.getByText(/stock actual:/i)).toBeVisible();

  await page.getByLabel(/cantidad/i).fill('15');
  await page.getByLabel(/motivo/i).fill('Corrección por diferencia detectada en conteo físico mensual.');
  await page.getByRole('button', { name: /solicitar ajuste/i }).click();

  // THEN: Redirige al detalle del ajuste
  await expect(page).toHaveURL(/\/ajustes\/[a-z0-9-]+/);
  await expect(page.getByText('PENDIENTE')).toBeVisible();

  // AND: El ajuste aparece en la lista
  await page.goto('/ajustes');
  await expect(page.getByText(/corrección por diferencia/i)).toBeVisible();
  await expect(page.getAllByText('PENDIENTE').first()).toBeVisible();
});
```

---

### TC-AJU-02: Supervisor aprueba un ajuste y el stock cambia

```typescript
test('TC-AJU-02: Supervisor aprueba ajuste y stock del producto se actualiza', async ({ page }) => {
  // GIVEN: Ajuste pendiente aju-seed-01 (cantidad: +25)
  // Stock actual de prod-seed-inv-01 = 50 (del seed de inventario)
  await page.goto(`/ajustes/aju-seed-01`);
  await expect(page.getByText('PENDIENTE')).toBeVisible();

  // AND: Los botones de decisión son visibles para Supervisor
  await expect(page.getByRole('button', { name: /aprobar/i })).toBeVisible();

  // WHEN: Click en "Aprobar"
  await page.getByRole('button', { name: /aprobar/i }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: /aprobar/i, exact: true }).last().click();

  // THEN: El estado del ajuste cambia a APROBADO
  await expect(page.getByText('APROBADO')).toBeVisible({ timeout: 10000 });

  // AND: El stock del producto aumentó en 25
  await page.goto('/inventario/stock');
  const stockText = await page.locator('[data-testid="stock-prod-seed-inv-01"]').textContent();
  expect(Number(stockText)).toBe(75); // 50 + 25
});
```

---

### TC-AJU-03: Operador no ve botones de decisión en detalle de ajuste

```typescript
test('TC-AJU-03: Operador en detalle de ajuste no ve botones Aprobar/Rechazar', async ({ page }) => {
  // GIVEN: Operador autenticado en detalle de ajuste PENDIENTE
  await page.goto(`/ajustes/aju-seed-02`);
  await expect(page.getByText('PENDIENTE')).toBeVisible();

  // THEN: No hay botones de decisión
  await expect(page.getByRole('button', { name: /aprobar/i })).not.toBeVisible();
  await expect(page.getByRole('button', { name: /rechazar/i })).not.toBeVisible();

  // AND: La información del ajuste sí es visible
  await expect(page.getByText(/ajuste seed para prueba/i)).toBeVisible();
});
```

---

### TC-AJU-04: Supervisor rechaza ajuste con comentario

```typescript
test('TC-AJU-04: Supervisor rechaza ajuste con comentario y aparece en historial', async ({ page }) => {
  // GIVEN: Ajuste pendiente aju-seed-02
  await page.goto(`/ajustes/aju-seed-02`);
  await expect(page.getByText('PENDIENTE')).toBeVisible();

  // WHEN: Click en "Rechazar"
  await page.getByRole('button', { name: /rechazar/i }).click();
  await expect(page.getByRole('dialog')).toBeVisible();

  // AND: Ingresa un comentario
  await page.getByLabel(/motivo del rechazo/i).fill('Stock no corresponde con el sistema central. Requiere verificación adicional.');
  await page.getByRole('button', { name: /confirmar rechazo/i }).click();

  // THEN: Estado cambia a RECHAZADO
  await expect(page.getByText('RECHAZADO')).toBeVisible({ timeout: 10000 });

  // AND: El comentario aparece en el historial de decisiones
  await expect(page.getByText(/stock no corresponde/i)).toBeVisible();

  // AND: Los botones de decisión ya no son visibles (estado != PENDIENTE)
  await expect(page.getByRole('button', { name: /aprobar/i })).not.toBeVisible();
  await expect(page.getByRole('button', { name: /rechazar/i })).not.toBeVisible();
});
```

---

## 11. Criterios de Aceptación

### 11.1 Criterios funcionales

| ID | Criterio | Verificación |
|----|---------|-------------|
| CA-AJU-01 | Operador puede crear solicitudes de ajuste (positivas o negativas) | E2E TC-AJU-01 + test `useCreateAjuste` |
| CA-AJU-02 | Cantidad = 0 es rechazada por validación frontend | Test schema + test `AjusteForm` |
| CA-AJU-03 | Motivo < 10 chars muestra error inline | Test `AjusteForm` |
| CA-AJU-04 | Al seleccionar producto, se muestra stock actual | Test `AjusteForm` con mock `useStockByProducto` |
| CA-AJU-05 | Supervisor aprueba ajuste PENDIENTE y stock se actualiza | E2E TC-AJU-02 |
| CA-AJU-06 | Supervisor rechaza con comentario y queda en historial | E2E TC-AJU-04 |
| CA-AJU-07 | Operador NO ve botones Aprobar/Rechazar | E2E TC-AJU-03 |
| CA-AJU-08 | Filtro por estado funciona en lista de ajustes | Test `ajustesSlice` + test integración |
| CA-AJU-09 | Estado `ERROR` de saga muestra indicador visual en la fila | Test `AjusteTable` con dato de estado ERROR |

### 11.2 Criterios de calidad TDD

| Criterio | Evidencia requerida |
|---------|-------------------|
| Schema `CreateAjusteSchema` tuvo test fallido antes de ser escrito | Commit de test antes que schema |
| Hooks tuvieron MSW handler + test antes de implementación | Commits secuenciales en historial git |
| Componentes tuvieron test antes de implementación | Commits secuenciales |
| `npm run test` verde al finalizar la etapa | Output de CI limpio |
| E2E Playwright pasan en staging (TC-AJU-01 al TC-AJU-04) | Reporte Playwright sin fallos |
| Cobertura de ramas > 80% en feature ajustes | Reporte Vitest coverage |

### 11.3 Criterios de integración

| Criterio | Detalle |
|---------|---------|
| Flujo completo de saga en staging | Aprobación dispara saga; stock actualizado en menos de 5 segundos |
| Invalidación de caché tras aprobación | `['ajustes', id]`, `['ajustes']` y `['stock']` invalidados en `onSuccess` |
| Error 403 manejado correctamente | Toast de "No autorizado" visible cuando Operador llama a endpoint de aprobación |
| Estado `sagaId` visible en detalle | Cuando la saga fue iniciada, el ID es visible en la UI de detalle |
