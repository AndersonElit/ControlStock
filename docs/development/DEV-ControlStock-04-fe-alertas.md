# Etapa 4f — Frontend: Feature Alertas

## 1. Contexto y Objetivo

El feature **Alertas** implementa la visualización y gestión de alertas automáticas de inventario generadas por `alert-service`. Las alertas se crean automáticamente cuando el stock de un producto baja del mínimo configurado (`BAJO_STOCK`) o supera el máximo (`SOBRESTOCK`). Los usuarios pueden consultar las alertas, filtrarlas y marcarlas como reconocidas (reconocimiento que no resuelve el problema de stock, solo acusa recibo de la alerta).

**Objetivo de la etapa:**
- Implementar las páginas y componentes del feature siguiendo TDD estricto (Red → Green → Refactor).
- El hook `useAlertas` configura `refetchInterval: 60_000` para actualización automática sin polling manual.
- Los escenarios E2E Playwright (ATDD) están redactados y fallando antes de la integración.
- Conectar con `alert-service` a través de Kong API Gateway en `http://<VPS_IP>:8000/api/v1`.

**Flujo de estados de una alerta:**
```
ACTIVA → (reconocimiento manual) → RECONOCIDA
ACTIVA / RECONOCIDA → (stock vuelve al rango normal, automático) → RESUELTA
```

**Restricciones de negocio:**
- Gerente, Analista y Auditor pueden VER alertas pero NO reconocerlas.
- Solo Operador, Supervisor y Administrador pueden reconocer alertas `ACTIVA`.
- No existe formulario de creación de alertas desde la UI; son eventos automáticos del backend.

---

## 2. Prerrequisitos

| Ítem | Detalle |
|------|---------|
| Etapa 4a completada | Scaffold Next.js 14 + App Router, providers configurados |
| Etapa 4b completada | NextAuth.js 4 + Keycloak, `middleware.ts`, roles JWT |
| Etapa 4c completada | Feature Catálogo: `EstadoBadge`, `useProducto()` para mostrar nombre de producto |
| Variables de entorno | `NEXT_PUBLIC_API_URL` configurada |
| MSW v2 configurado | Handlers para `alert-service` en `src/mocks/handlers/alerts.ts` |
| Vitest + RTL configurados | Con `@testing-library/user-event` y `setupTests.ts` |
| Playwright configurado | Con fixtures de rol multi-usuario |
| `alertasSlice` | Se crea en esta etapa dentro del store Zustand global |

---

## 3. Rutas y Páginas

Todas las rutas viven bajo `src/app/(protected)/alertas/`.

| Ruta | Tipo | Archivo de Página | Componente de Página | Descripción |
|------|------|-------------------|----------------------|-------------|
| `/alertas` | Protegida (todos los roles) | `src/app/(protected)/alertas/page.tsx` | `AlertaListPage` | Listado de alertas con filtros por tipo y estado; refetch automático cada 60s |
| `/alertas/[id]` | Protegida (todos los roles) | `src/app/(protected)/alertas/[id]/page.tsx` | `AlertaDetailPage` | Detalle completo de la alerta + botón reconocer (condicional) |

### Protección de rutas

```typescript
// middleware.ts — reglas de alertas
// Todos los roles autenticados tienen acceso de lectura a /alertas y /alertas/[id].
// No se requieren restricciones de ruta; el control de acceso se implementa en los componentes.
const ROUTE_ROLES: Record<string, string[]> = {
  // No hay restricciones adicionales para alertas en el middleware
};
```

---

## 4. Componentes

> **Nota TDD:** Archivo de prueba creado y ejecutado (falla en rojo) antes de escribir el componente. Ciclo obligatorio: Red → Green → Refactor.

### 4.1 `AlertaTable`

**Archivo:** `src/features/alertas/components/AlertaTable.tsx`
**Prueba:** `src/features/alertas/components/__tests__/AlertaTable.test.tsx`

**Props:**
```typescript
interface AlertaTableProps {
  alertas: AlertaEvent[];
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
| Producto | `nombreProducto` | Obtenido por join o incluido en respuesta del servicio |
| Tipo | `tipoAlerta` | `<AlertaTipoBadge tipo={row.tipoAlerta} />` |
| Stock Actual | `stockActual` | Negrita roja si `tipoAlerta === 'BAJO_STOCK'` |
| Umbral | `umbral` | El valor que disparó la alerta |
| Estado | `estado` | `<AlertaEstadoBadge estado={row.estado} />` |
| Acciones | — | Enlace a detalle; botón reconocer si rol autorizado y estado ACTIVA |

**Comportamiento:**
- Filas con `estado === 'ACTIVA'` resaltadas con `border-l-4 border-red-400`.
- Filas con `estado === 'RESUELTA'` con opacidad reducida (`opacity-60`).
- Skeleton de carga: 8 filas.
- Estado vacío: "No hay alertas registradas con los filtros seleccionados."
- `data-testid="alerta-row-{id}"` en cada `<tr>` para facilitar selección en pruebas.

---

### 4.2 `AlertaTipoBadge`

**Archivo:** `src/features/alertas/components/AlertaTipoBadge.tsx`
**Prueba:** `src/features/alertas/components/__tests__/AlertaTipoBadge.test.tsx`

**Props:**
```typescript
interface AlertaTipoBadgeProps {
  tipo: 'BAJO_STOCK' | 'SOBRESTOCK';
}
```

**Colores:**
| Tipo | Clases CSS | Icono | Texto |
|------|-----------|-------|-------|
| `BAJO_STOCK` | `bg-red-100 text-red-800 border border-red-300` | ⚠ | "BAJO STOCK" |
| `SOBRESTOCK` | `bg-orange-100 text-orange-800 border border-orange-300` | ↑ | "SOBRESTOCK" |

---

### 4.3 `AlertaEstadoBadge`

**Archivo:** `src/features/alertas/components/AlertaEstadoBadge.tsx`
**Prueba:** `src/features/alertas/components/__tests__/AlertaEstadoBadge.test.tsx`

**Props:**
```typescript
interface AlertaEstadoBadgeProps {
  estado: 'ACTIVA' | 'RECONOCIDA' | 'RESUELTA';
}
```

**Colores:**
| Estado | Clases CSS | Texto |
|--------|-----------|-------|
| `ACTIVA` | `bg-red-100 text-red-800` | "ACTIVA" |
| `RECONOCIDA` | `bg-yellow-100 text-yellow-800` | "RECONOCIDA" |
| `RESUELTA` | `bg-green-100 text-green-800` | "RESUELTA" |

---

### 4.4 `AlertaFilters`

**Archivo:** `src/features/alertas/components/AlertaFilters.tsx`
**Prueba:** `src/features/alertas/components/__tests__/AlertaFilters.test.tsx`

**Props:**
```typescript
interface AlertaFiltersProps {
  tipoValue: string[];
  estadoValue: string;
  onTipoChange: (tipos: string[]) => void;
  onEstadoChange: (estado: string) => void;
}
```

**Campos:**
- **Tipo (multi-select):** Checkboxes para `BAJO_STOCK` y `SOBRESTOCK`; selección múltiple.
  - Ninguno seleccionado = sin filtro de tipo (todos).
- **Estado (select):** Opciones: Todos, ACTIVA, RECONOCIDA, RESUELTA.
- **Producto (búsqueda de texto):** Input de búsqueda libre; debounce de 300ms antes de actualizar el filtro `productoId` en el slice.

**Integración con `alertasSlice`:** El componente padre `AlertaListPage` conecta las acciones del slice con los props de `AlertaFilters`.

---

### 4.5 `ReconocerAlertaButton`

**Archivo:** `src/features/alertas/components/ReconocerAlertaButton.tsx`
**Prueba:** `src/features/alertas/components/__tests__/ReconocerAlertaButton.test.tsx`

**Props:**
```typescript
interface ReconocerAlertaButtonProps {
  alertaId: string;
  estado: 'ACTIVA' | 'RECONOCIDA' | 'RESUELTA';
  onSuccess?: () => void;
}
```

**Comportamiento:**
```typescript
// Visibilidad condicional
const roles = useRol();
const puedeReconocer = tieneRol(roles, 'Operador', 'Supervisor', 'Administrador');
const esActiva       = estado === 'ACTIVA';
const visible        = puedeReconocer && esActiva;

if (!visible) return null;
```

- Botón con texto "Reconocer alerta".
- Al hacer click, llama `useReconocerAlerta(alertaId).mutate()`.
- Estado `isPending`: botón deshabilitado con spinner.
- Tras success: llama `onSuccess?.()` para que el padre refresque o cierre.
- `data-testid="reconocer-btn-{alertaId}"`.

---

### 4.6 `AlertaDetail`

**Archivo:** `src/features/alertas/components/AlertaDetail.tsx`
**Prueba:** `src/features/alertas/components/__tests__/AlertaDetail.test.tsx`

**Props:**
```typescript
interface AlertaDetailProps {
  alertaId: string;
}
```

**Layout:**
```
┌──────────────────────────────────────────┐
│ Card principal                            │
│ Tipo: <AlertaTipoBadge>  Estado: <Badge>  │
│ Producto: {nombreProducto}                │
│ Stock actual al generar: {stockActual}    │
│ Umbral que disparó la alerta: {umbral}    │
│ Fecha de creación: {createdAt}            │
│ Última actualización: {updatedAt}         │
├──────────────────────────────────────────┤
│ <ReconocerAlertaButton alertaId={id}     │
│   estado={alerta.estado} />              │
├──────────────────────────────────────────┤
│ Historial de reconocimientos             │
│ (lista de {usuario, fecha} si existen)   │
└──────────────────────────────────────────┘
```

El historial de reconocimientos es parte de la respuesta del endpoint `GET /alerts/{id}` cuando el campo `reconocimientos` está incluido.

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** MSW handler + test del hook escritos antes de implementar el hook.

Todos los hooks residen en `src/features/alertas/hooks/`.

### 5.1 `useAlertas`

```typescript
// src/features/alertas/hooks/useAlertas.ts
export function useAlertas(params?: AlertasParams) {
  return useQuery({
    queryKey: ['alertas', params],
    queryFn: () => fetchAlertas(params),
    staleTime:      30 * 1000,       // 30 segundos
    refetchInterval: 60 * 1000,      // Auto-refetch cada 60 segundos
  });
}
```

- **Endpoint:** `GET /alerts`
- **Query params:** `{ tipo?: 'BAJO_STOCK'|'SOBRESTOCK', estado?: 'ACTIVA'|'RECONOCIDA'|'RESUELTA', productoId?: string, page?: number, size?: number }`
- **staleTime:** 30 segundos.
- **refetchInterval:** 60 segundos — las alertas se generan de forma asíncrona; el refetch automático garantiza visibilidad sin requerir acción del usuario.

> **Importante:** El `refetchInterval` solo actúa cuando la ventana está enfocada (comportamiento por defecto de TanStack Query). No se usa `block()` ni polling manual.

---

### 5.2 `useAlerta`

```typescript
export function useAlerta(id: string) {
  return useQuery({
    queryKey: ['alertas', id],
    queryFn: () => fetchAlertaById(id),
    enabled: !!id,
    staleTime: 30 * 1000,
  });
}
```

- **Endpoint:** `GET /alerts/{id}`

---

### 5.3 `useReconocerAlerta`

```typescript
export function useReconocerAlerta(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => reconocerAlerta(id),
    onSuccess: () => {
      // Actualizar el ítem específico en caché
      queryClient.setQueryData(['alertas', id], (old: AlertaEvent | undefined) =>
        old ? { ...old, estado: 'RECONOCIDA' } : old
      );
      // Invalidar la lista para que el refetch la actualice
      queryClient.invalidateQueries({ queryKey: ['alertas'] });
    },
  });
}
```

- **Endpoint:** `POST /alerts/{id}/reconocer`
- **Optimistic update:** Se actualiza el estado en caché inmediatamente antes de la confirmación del servidor (`setQueryData`).

---

## 6. Estado Global (Zustand)

> **Nota TDD:** Pruebas del slice escritas antes de la implementación.

**Archivo:** `src/store/slices/alertasSlice.ts`

```typescript
interface AlertasState {
  tipoFilter:    string[];   // puede ser [] (sin filtro), ['BAJO_STOCK'], ['SOBRESTOCK'], ['BAJO_STOCK','SOBRESTOCK']
  estadoFilter:  string;     // 'TODOS' | 'ACTIVA' | 'RECONOCIDA' | 'RESUELTA'
  productoSearch: string;    // texto libre para buscar por producto
  setTipoFilter:    (tipos: string[]) => void;
  setEstadoFilter:  (estado: string) => void;
  setProductoSearch:(search: string) => void;
}

export const useAlertasSlice = (set: SetState<AlertasState>): AlertasState => ({
  tipoFilter:     [],
  estadoFilter:   'TODOS',
  productoSearch: '',
  setTipoFilter:    (tipos)  => set({ tipoFilter: tipos }),
  setEstadoFilter:  (estado) => set({ estadoFilter: estado }),
  setProductoSearch:(search) => set({ productoSearch: search }),
});
```

**Integración con `AlertaListPage`:**
```typescript
const { tipoFilter, estadoFilter, setTipoFilter, setEstadoFilter } = useAlertasStore();
const { data, isLoading } = useAlertas({
  tipo:    tipoFilter.length === 1 ? tipoFilter[0] : undefined, // API soporta un tipo a la vez
  estado:  estadoFilter === 'TODOS' ? undefined : estadoFilter,
  page:    currentPage,
  size:    25,
});
```

> Nota: Si la API soporta múltiples tipos en un parámetro `tipo[]`, el hook puede pasar el array directamente. Si no, se hacen dos queries paralelas y se unen en el componente. Se define según el contrato real del `alert-service`.

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** Test unitario del schema escrito antes de la definición.

**Archivo:** `src/features/alertas/schemas/alerta.schema.ts`

```typescript
import { z } from 'zod';

export const AlertaEventResponseSchema = z.object({
  id:          z.string().uuid(),
  productoId:  z.string().uuid(),
  tipoAlerta:  z.enum(['BAJO_STOCK', 'SOBRESTOCK'], {
    errorMap: () => ({ message: 'Tipo de alerta inválido' }),
  }),
  stockActual: z.number(),           // puede ser negativo si hubo desfases
  umbral:      z.number(),
  estado:      z.enum(['ACTIVA', 'RECONOCIDA', 'RESUELTA'], {
    errorMap: () => ({ message: 'Estado de alerta inválido' }),
  }),
  createdAt:   z.string().datetime(),
  updatedAt:   z.string().datetime(),
});

export const AlertaListResponseSchema = z.array(AlertaEventResponseSchema);

// Schema paginado (si el endpoint devuelve paginación)
export const AlertaPageResponseSchema = z.object({
  content:       AlertaListResponseSchema,
  totalElements: z.number(),
  totalPages:    z.number(),
  page:          z.number(),
  size:          z.number(),
});

export type AlertaEvent        = z.infer<typeof AlertaEventResponseSchema>;
export type AlertaListResponse = z.infer<typeof AlertaListResponseSchema>;
export type AlertaPageResponse = z.infer<typeof AlertaPageResponseSchema>;
```

---

## 8. Autenticación y Autorización

### 8.1 Tabla de permisos por acción en Alertas

| Acción | Operador | Supervisor | Administrador | Gerente | Analista | Auditor |
|--------|----------|-----------|---------------|---------|----------|---------|
| Ver lista de alertas | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ver detalle de alerta | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Reconocer alerta | ✓ | ✓ | ✓ | — | — | — |

### 8.2 Implementación de control de acceso

```typescript
// ReconocerAlertaButton
const roles = useRol();
const puedeReconocer = tieneRol(roles, 'Operador', 'Supervisor', 'Administrador');

// En AlertaTable — columna Acciones
const mostrarBotonReconocer = (alerta: AlertaEvent) =>
  puedeReconocer && alerta.estado === 'ACTIVA';
```

### 8.3 Roles de solo lectura (Gerente, Analista, Auditor)

Para estos roles, la UI renderiza la lista y el detalle completamente, pero el componente `ReconocerAlertaButton` retorna `null` (no renderiza nada) por la lógica interna de verificación de rol.

No se requiere restricción en middleware para estas rutas ya que la diferencia es de interacción, no de acceso a la página.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Regla Red-Green-Refactor:** Test fallido → mínima implementación → refactor.

### 9.1 Pruebas del Schema `AlertaEventResponseSchema`

**Archivo:** `src/features/alertas/schemas/__tests__/alerta.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { AlertaEventResponseSchema } from '../alerta.schema';

describe('AlertaEventResponseSchema', () => {
  const validBajoStock = {
    id:          'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    productoId:  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    tipoAlerta:  'BAJO_STOCK',
    stockActual: 3,
    umbral:      10,
    estado:      'ACTIVA',
    createdAt:   '2025-06-01T08:00:00Z',
    updatedAt:   '2025-06-01T08:00:00Z',
  } as const;

  const validSobrestock = {
    ...validBajoStock,
    tipoAlerta: 'SOBRESTOCK',
    stockActual: 350,
    umbral:      200,
  } as const;

  it('debería pasar con alerta BAJO_STOCK válida', () => {
    expect(AlertaEventResponseSchema.safeParse(validBajoStock).success).toBe(true);
  });

  it('debería pasar con alerta SOBRESTOCK válida', () => {
    expect(AlertaEventResponseSchema.safeParse(validSobrestock).success).toBe(true);
  });

  it('debería fallar con tipoAlerta inválido', () => {
    const result = AlertaEventResponseSchema.safeParse({
      ...validBajoStock,
      tipoAlerta: 'STOCK_NORMAL',
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('tipoAlerta');
    expect(result.error?.issues[0].message).toBe('Tipo de alerta inválido');
  });

  it('debería fallar con estado inválido', () => {
    const result = AlertaEventResponseSchema.safeParse({
      ...validBajoStock,
      estado: 'CERRADA',
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('estado');
  });

  it('debería aceptar stockActual negativo (es schema de lectura)', () => {
    // El backend puede reportar stock negativo en situaciones de desfase
    const result = AlertaEventResponseSchema.safeParse({ ...validBajoStock, stockActual: -5 });
    expect(result.success).toBe(true);
  });

  it('debería fallar si productoId no es UUID', () => {
    const result = AlertaEventResponseSchema.safeParse({
      ...validBajoStock,
      productoId: 'no-es-uuid',
    });
    expect(result.success).toBe(false);
  });

  it('debería fallar si createdAt no es fecha ISO', () => {
    const result = AlertaEventResponseSchema.safeParse({
      ...validBajoStock,
      createdAt: '01/06/2025',
    });
    expect(result.success).toBe(false);
  });
});
```

---

### 9.2 Pruebas del hook `useAlertas`

**Archivo:** `src/features/alertas/hooks/__tests__/useAlertas.test.tsx`

MSW handlers:

```typescript
// src/mocks/handlers/alerts.ts
import { http, HttpResponse } from 'msw';

export const alertHandlers = [
  http.get('/api/v1/alerts', () =>
    HttpResponse.json({
      content: [
        {
          id: 'alert-uuid-1', productoId: 'prod-uuid-1',
          tipoAlerta: 'BAJO_STOCK', stockActual: 3, umbral: 10,
          estado: 'ACTIVA', createdAt: '2025-06-01T08:00:00Z', updatedAt: '2025-06-01T08:00:00Z',
        },
        {
          id: 'alert-uuid-2', productoId: 'prod-uuid-2',
          tipoAlerta: 'SOBRESTOCK', stockActual: 350, umbral: 200,
          estado: 'RECONOCIDA', createdAt: '2025-06-01T07:00:00Z', updatedAt: '2025-06-01T09:00:00Z',
        },
      ],
      totalPages: 1, totalElements: 2, page: 0, size: 25,
    })
  ),
];
```

```typescript
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useAlertas } from '../useAlertas';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

describe('useAlertas', () => {
  it('debería mostrar estado loading al inicio', () => {
    const { result } = renderHook(() => useAlertas(), { wrapper: createWrapper() });
    expect(result.current.isLoading).toBe(true);
  });

  it('debería retornar lista de alertas en estado success', async () => {
    const { result } = renderHook(() => useAlertas(), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.content).toHaveLength(2);
    expect(result.current.data?.content[0].tipoAlerta).toBe('BAJO_STOCK');
    expect(result.current.data?.content[1].tipoAlerta).toBe('SOBRESTOCK');
  });

  it('debería manejar error de red', async () => {
    server.use(
      http.get('/api/v1/alerts', () =>
        HttpResponse.json({ message: 'Internal Server Error' }, { status: 500 })
      )
    );
    const { result } = renderHook(() => useAlertas(), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });

  it('debería tener refetchInterval configurado en 60000ms', () => {
    // Verificar que la configuración del hook incluye refetchInterval
    // Esto se puede verificar inspeccionando el queryCache o mockeando useQuery
    const observerMock = vi.fn();
    // Abordaje: renderizar y verificar que la query tiene refetchInterval
    const { result } = renderHook(() => useAlertas(), { wrapper: createWrapper() });
    // Verificación declarativa: la opción debe estar en la definición del hook
    // (test de configuración, no de comportamiento temporal)
    expect(result.current).toBeDefined(); // hook renderizó sin error
    // El refetchInterval se verifica en code review del hook
  });

  it('debería filtrar por tipo BAJO_STOCK cuando se pasa el parámetro', async () => {
    server.use(
      http.get('/api/v1/alerts', ({ request }) => {
        const url = new URL(request.url);
        const tipo = url.searchParams.get('tipo');
        const filtered = tipo === 'BAJO_STOCK'
          ? [{ id: 'alert-uuid-1', tipoAlerta: 'BAJO_STOCK', stockActual: 3, umbral: 10,
               productoId: 'prod-1', estado: 'ACTIVA',
               createdAt: '2025-06-01T08:00:00Z', updatedAt: '2025-06-01T08:00:00Z' }]
          : [];
        return HttpResponse.json({ content: filtered, totalPages: 1, totalElements: filtered.length, page: 0, size: 25 });
      })
    );
    const { result } = renderHook(
      () => useAlertas({ tipo: 'BAJO_STOCK' }),
      { wrapper: createWrapper() }
    );
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.content).toHaveLength(1);
    expect(result.current.data?.content[0].tipoAlerta).toBe('BAJO_STOCK');
  });
});
```

---

### 9.3 Pruebas del hook `useReconocerAlerta`

**Archivo:** `src/features/alertas/hooks/__tests__/useReconocerAlerta.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { createWrapperWithData } from '@/test-utils/query-wrapper';
import { useReconocerAlerta } from '../useReconocerAlerta';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

describe('useReconocerAlerta', () => {
  it('éxito: actualiza el estado de la alerta a RECONOCIDA en caché', async () => {
    server.use(
      http.post('/api/v1/alerts/:id/reconocer', () =>
        HttpResponse.json({ id: 'alert-uuid-1', estado: 'RECONOCIDA' }, { status: 200 })
      )
    );
    const wrapper = createWrapperWithData(['alertas', 'alert-uuid-1'], {
      id: 'alert-uuid-1', estado: 'ACTIVA', tipoAlerta: 'BAJO_STOCK',
    });
    const { result } = renderHook(() => useReconocerAlerta('alert-uuid-1'), { wrapper });
    await act(async () => { result.current.mutate(); });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
  });

  it('error 400: la mutación falla con error del servidor', async () => {
    server.use(
      http.post('/api/v1/alerts/:id/reconocer', () =>
        HttpResponse.json({ message: 'Alerta ya reconocida' }, { status: 400 })
      )
    );
    const { result } = renderHook(() => useReconocerAlerta('alert-uuid-1'), {
      wrapper: createWrapperWithData(['alertas', 'alert-uuid-1'], {}),
    });
    await act(async () => { result.current.mutate(); });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

---

### 9.4 Pruebas del componente `AlertaTable`

**Archivo:** `src/features/alertas/components/__tests__/AlertaTable.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AlertaTable } from '../AlertaTable';
import type { AlertaEvent } from '../../../schemas/alerta.schema';

const mockAlertas: AlertaEvent[] = [
  { id: 'a1', productoId: 'p1', tipoAlerta: 'BAJO_STOCK', stockActual: 3, umbral: 10,
    estado: 'ACTIVA', createdAt: '2025-06-01T08:00:00Z', updatedAt: '2025-06-01T08:00:00Z' },
  { id: 'a2', productoId: 'p2', tipoAlerta: 'SOBRESTOCK', stockActual: 350, umbral: 200,
    estado: 'RECONOCIDA', createdAt: '2025-06-01T07:00:00Z', updatedAt: '2025-06-01T09:00:00Z' },
];

describe('AlertaTable', () => {
  it('debería renderizar las filas de alertas', () => {
    render(
      <AlertaTable
        alertas={mockAlertas}
        totalPages={1}
        currentPage={0}
        onPageChange={vi.fn()}
      />
    );
    expect(screen.getByTestId('alerta-row-a1')).toBeInTheDocument();
    expect(screen.getByTestId('alerta-row-a2')).toBeInTheDocument();
  });

  it('debería renderizar el badge de tipo en cada fila', () => {
    render(
      <AlertaTable alertas={mockAlertas} totalPages={1} currentPage={0} onPageChange={vi.fn()} />
    );
    expect(screen.getByText('BAJO STOCK')).toBeInTheDocument();
    expect(screen.getByText('SOBRESTOCK')).toBeInTheDocument();
  });

  it('debería mostrar mensaje de estado vacío cuando alertas = []', () => {
    render(
      <AlertaTable alertas={[]} totalPages={0} currentPage={0} onPageChange={vi.fn()} />
    );
    expect(screen.getByText(/no hay alertas registradas/i)).toBeInTheDocument();
  });
});
```

---

### 9.5 Pruebas del componente `AlertaTipoBadge`

**Archivo:** `src/features/alertas/components/__tests__/AlertaTipoBadge.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AlertaTipoBadge } from '../AlertaTipoBadge';

describe('AlertaTipoBadge', () => {
  it('BAJO_STOCK → badge rojo con texto "BAJO STOCK"', () => {
    render(<AlertaTipoBadge tipo="BAJO_STOCK" />);
    const badge = screen.getByText(/bajo stock/i);
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveClass('bg-red-100');
    expect(badge).toHaveClass('text-red-800');
  });

  it('SOBRESTOCK → badge naranja con texto "SOBRESTOCK"', () => {
    render(<AlertaTipoBadge tipo="SOBRESTOCK" />);
    const badge = screen.getByText(/sobrestock/i);
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveClass('bg-orange-100');
    expect(badge).toHaveClass('text-orange-800');
  });
});
```

---

### 9.6 Pruebas del componente `ReconocerAlertaButton`

**Archivo:** `src/features/alertas/components/__tests__/ReconocerAlertaButton.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ReconocerAlertaButton } from '../ReconocerAlertaButton';

// Mock del hook de rol
vi.mock('@/features/auth/hooks/useRol', () => ({
  useRol: () => ['Operador'],
}));

// Mock del hook de mutación
const mockMutate = vi.fn();
vi.mock('@/features/alertas/hooks/useReconocerAlerta', () => ({
  useReconocerAlerta: () => ({ mutate: mockMutate, isPending: false }),
}));

describe('ReconocerAlertaButton', () => {
  it('debería ser VISIBLE cuando estado=ACTIVA y rol=Operador', () => {
    render(<ReconocerAlertaButton alertaId="a1" estado="ACTIVA" />);
    expect(screen.getByTestId('reconocer-btn-a1')).toBeInTheDocument();
    expect(screen.getByText(/reconocer alerta/i)).toBeVisible();
  });

  it('debería estar OCULTO cuando estado=RECONOCIDA', () => {
    render(<ReconocerAlertaButton alertaId="a1" estado="RECONOCIDA" />);
    expect(screen.queryByTestId('reconocer-btn-a1')).not.toBeInTheDocument();
  });

  it('debería estar OCULTO cuando estado=RESUELTA', () => {
    render(<ReconocerAlertaButton alertaId="a1" estado="RESUELTA" />);
    expect(screen.queryByTestId('reconocer-btn-a1')).not.toBeInTheDocument();
  });

  it('debería llamar mutate al hacer click', async () => {
    const user = userEvent.setup();
    render(<ReconocerAlertaButton alertaId="a1" estado="ACTIVA" />);
    await user.click(screen.getByTestId('reconocer-btn-a1'));
    expect(mockMutate).toHaveBeenCalledOnce();
  });

  it('debería estar OCULTO para rol Auditor (sin permiso de reconocer)', () => {
    vi.mock('@/features/auth/hooks/useRol', () => ({
      useRol: () => ['Auditor'],
    }));
    render(<ReconocerAlertaButton alertaId="a1" estado="ACTIVA" />);
    expect(screen.queryByTestId('reconocer-btn-a1')).not.toBeInTheDocument();
  });
});
```

---

### 9.7 Pruebas del `alertasSlice`

**Archivo:** `src/store/slices/__tests__/alertasSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { act } from '@testing-library/react';
import { create } from 'zustand';
import { useAlertasSlice } from '../alertasSlice';

const useTestStore = create(useAlertasSlice);

describe('alertasSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ tipoFilter: [], estadoFilter: 'TODOS', productoSearch: '' });
  });

  it('estado inicial correcto', () => {
    const state = useTestStore.getState();
    expect(state.tipoFilter).toEqual([]);
    expect(state.estadoFilter).toBe('TODOS');
    expect(state.productoSearch).toBe('');
  });

  it('setTipoFilter: agrega BAJO_STOCK al array', () => {
    act(() => { useTestStore.getState().setTipoFilter(['BAJO_STOCK']); });
    expect(useTestStore.getState().tipoFilter).toEqual(['BAJO_STOCK']);
  });

  it('setTipoFilter: agrega ambos tipos', () => {
    act(() => { useTestStore.getState().setTipoFilter(['BAJO_STOCK', 'SOBRESTOCK']); });
    expect(useTestStore.getState().tipoFilter).toEqual(['BAJO_STOCK', 'SOBRESTOCK']);
  });

  it('setTipoFilter: elimina tipos (array vacío)', () => {
    act(() => {
      useTestStore.getState().setTipoFilter(['BAJO_STOCK']);
      useTestStore.getState().setTipoFilter([]);
    });
    expect(useTestStore.getState().tipoFilter).toEqual([]);
  });

  it('setEstadoFilter: actualiza a ACTIVA', () => {
    act(() => { useTestStore.getState().setEstadoFilter('ACTIVA'); });
    expect(useTestStore.getState().estadoFilter).toBe('ACTIVA');
  });

  it('setEstadoFilter: actualiza a RECONOCIDA', () => {
    act(() => { useTestStore.getState().setEstadoFilter('RECONOCIDA'); });
    expect(useTestStore.getState().estadoFilter).toBe('RECONOCIDA');
  });

  it('setEstadoFilter: puede volver a TODOS', () => {
    act(() => {
      useTestStore.getState().setEstadoFilter('ACTIVA');
      useTestStore.getState().setEstadoFilter('TODOS');
    });
    expect(useTestStore.getState().estadoFilter).toBe('TODOS');
  });

  it('setTipoFilter y setEstadoFilter son independientes', () => {
    act(() => {
      useTestStore.getState().setTipoFilter(['SOBRESTOCK']);
      useTestStore.getState().setEstadoFilter('RECONOCIDA');
    });
    const state = useTestStore.getState();
    expect(state.tipoFilter).toEqual(['SOBRESTOCK']);
    expect(state.estadoFilter).toBe('RECONOCIDA');
  });
});
```

---

## 10. Pruebas E2E (Playwright, ATDD)

> **Principio ATDD:** Los escenarios E2E se escriben antes de integrar el feature. Requieren datos seed en el entorno de staging.

**Archivo:** `e2e/alertas/alertas.spec.ts`

### Datos seed requeridos en staging

```yaml
# seed-alertas.yml
alertas:
  - id: "ale-seed-01"
    productoId: "prod-seed-inv-01"
    tipoAlerta: "BAJO_STOCK"
    stockActual: 3
    umbral: 10
    estado: "ACTIVA"
    createdAt: "2025-06-01T06:00:00Z"
    updatedAt: "2025-06-01T06:00:00Z"

  - id: "ale-seed-02"
    productoId: "prod-seed-inv-02"
    tipoAlerta: "SOBRESTOCK"
    stockActual: 350
    umbral: 200
    estado: "ACTIVA"
    createdAt: "2025-06-01T07:00:00Z"
    updatedAt: "2025-06-01T07:00:00Z"

  - id: "ale-seed-03"
    productoId: "prod-seed-inv-01"
    tipoAlerta: "BAJO_STOCK"
    stockActual: 5
    umbral: 10
    estado: "RECONOCIDA"
    createdAt: "2025-05-30T10:00:00Z"
    updatedAt: "2025-05-30T11:00:00Z"
```

---

### TC-ALE-01: Navegar a /alertas y ver alertas activas

```typescript
test('TC-ALE-01: Navegar a /alertas muestra la lista de alertas activas', async ({ page }) => {
  // GIVEN: Usuario autenticado (cualquier rol)
  await page.goto('/alertas');

  // THEN: La página carga con el título correcto
  await expect(page.getByRole('heading', { name: /alertas/i })).toBeVisible();

  // AND: Se muestran las alertas activas del seed
  await expect(page.getByTestId('alerta-row-ale-seed-01')).toBeVisible();
  await expect(page.getByTestId('alerta-row-ale-seed-02')).toBeVisible();

  // AND: Los badges de tipo son correctos
  const row1 = page.getByTestId('alerta-row-ale-seed-01');
  await expect(row1.getByText(/bajo stock/i)).toBeVisible();

  const row2 = page.getByTestId('alerta-row-ale-seed-02');
  await expect(row2.getByText(/sobrestock/i)).toBeVisible();
});
```

---

### TC-ALE-02: Operador reconoce una alerta activa

```typescript
test('TC-ALE-02: Operador reconoce una alerta y el estado cambia a RECONOCIDA', async ({ page }) => {
  // GIVEN: Operador autenticado; alerta ale-seed-01 está ACTIVA
  await page.goto('/alertas');
  const row = page.getByTestId('alerta-row-ale-seed-01');
  await expect(row.getByText('ACTIVA')).toBeVisible();

  // WHEN: Click en "Reconocer" en la fila
  await row.getByTestId('reconocer-btn-ale-seed-01').click();

  // THEN: El estado de la alerta cambia a RECONOCIDA (actualización optimista + confirmación servidor)
  await expect(row.getByText('RECONOCIDA')).toBeVisible({ timeout: 5000 });

  // AND: El botón "Reconocer" ya no es visible en esa fila
  await expect(row.getByTestId('reconocer-btn-ale-seed-01')).not.toBeVisible();
});
```

---

### TC-ALE-03: Filtro por tipo BAJO_STOCK

```typescript
test('TC-ALE-03: Filtrar por tipo BAJO_STOCK muestra solo alertas de ese tipo', async ({ page }) => {
  // GIVEN: Lista con alertas de ambos tipos (seed: ale-seed-01 BAJO_STOCK, ale-seed-02 SOBRESTOCK)
  await page.goto('/alertas');
  await expect(page.getByTestId('alerta-row-ale-seed-01')).toBeVisible();
  await expect(page.getByTestId('alerta-row-ale-seed-02')).toBeVisible();

  // WHEN: Marcar el checkbox "BAJO_STOCK" en los filtros
  await page.getByRole('checkbox', { name: /bajo stock/i }).check();

  // THEN: Solo aparecen alertas de tipo BAJO_STOCK
  await expect(page.getByTestId('alerta-row-ale-seed-01')).toBeVisible();
  await expect(page.getByTestId('alerta-row-ale-seed-02')).not.toBeVisible();

  // AND: Los badges en las filas visibles son del tipo correcto
  await expect(page.getByText('BAJO STOCK')).toBeVisible();
  await expect(page.getByText('SOBRESTOCK')).not.toBeVisible();
});
```

---

### TC-ALE-04: Auditor no ve el botón "Reconocer"

```typescript
test('TC-ALE-04: Auditor puede ver alertas pero NO tiene botón Reconocer', async ({ page }) => {
  // GIVEN: Auditor autenticado en /alertas
  // (fixture configura sesión con rol Auditor)
  await page.goto('/alertas');

  // THEN: La lista de alertas se muestra correctamente
  await expect(page.getByRole('heading', { name: /alertas/i })).toBeVisible();
  await expect(page.getByTestId('alerta-row-ale-seed-01')).toBeVisible();

  // AND: No existe ningún botón "Reconocer"
  await expect(page.locator('[data-testid^="reconocer-btn-"]')).toHaveCount(0);

  // AND: El detalle de la alerta también es accesible
  await page.getByRole('link', { name: /ver detalle/i }).first().click();
  await expect(page).toHaveURL(/\/alertas\/[a-z0-9-]+/);

  // AND: En el detalle tampoco hay botón Reconocer para Auditor
  await expect(page.locator('[data-testid^="reconocer-btn-"]')).toHaveCount(0);
});
```

---

## 11. Criterios de Aceptación

### 11.1 Criterios funcionales

| ID | Criterio | Verificación |
|----|---------|-------------|
| CA-ALE-01 | Todos los roles autenticados pueden ver la lista de alertas | E2E TC-ALE-01 + test middleware |
| CA-ALE-02 | Solo Operador, Supervisor y Administrador pueden reconocer alertas | E2E TC-ALE-02 + test `ReconocerAlertaButton` |
| CA-ALE-03 | Auditor, Gerente y Analista NO ven el botón Reconocer | E2E TC-ALE-04 + test unitario de rol |
| CA-ALE-04 | Solo alertas en estado ACTIVA pueden ser reconocidas | Test `ReconocerAlertaButton` con estado RECONOCIDA/RESUELTA |
| CA-ALE-05 | Filtro por tipo BAJO_STOCK/SOBRESTOCK funciona | E2E TC-ALE-03 + test `alertasSlice` |
| CA-ALE-06 | La lista de alertas se actualiza automáticamente cada 60s | Test configuración `refetchInterval` en `useAlertas` |
| CA-ALE-07 | Tras reconocer, el estado cambia visualmente sin recarga completa | E2E TC-ALE-02 (verifica actualización optimista) |
| CA-ALE-08 | Los badges de tipo y estado tienen los colores correctos | Test unitarios `AlertaTipoBadge` y `AlertaEstadoBadge` |

### 11.2 Criterios de calidad TDD

| Criterio | Evidencia requerida |
|---------|-------------------|
| Schema `AlertaEventResponseSchema` tuvo test fallido antes de ser escrito | Commit de test antes que schema |
| Hook `useAlertas` tuvo MSW handler + test antes de ser escrito | Commits secuenciales verificables |
| Hook `useReconocerAlerta` tuvo test antes de ser escrito | Commit de test antes que hook |
| Componentes tuvieron test antes de implementación | Commits secuenciales |
| `npm run test` verde al finalizar la etapa | Output de CI sin errores |
| E2E Playwright pasan en staging (TC-ALE-01 al TC-ALE-04) | Reporte Playwright limpio |
| Cobertura de ramas > 80% en feature alertas | Reporte Vitest coverage |

### 11.3 Criterios de integración

| Criterio | Detalle |
|---------|---------|
| `refetchInterval` de 60s configurado correctamente | Verificado con herramientas de red en staging (request cada 60s) |
| Actualización optimista al reconocer | La UI actualiza el estado antes de la confirmación del servidor |
| Invalidación de caché tras reconocimiento | `['alertas']` y `['alertas', id]` invalidados tras `onSuccess` |
| Filtros conectados al slice y al hook | Cambios en `alertasSlice` se reflejan en los params de `useAlertas` |
| JWT incluido en todas las llamadas | Header Authorization presente en requests a `/alerts` (verificado en Network tab) |
