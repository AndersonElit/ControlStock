# Etapa 4d — Frontend: Feature Inventario

## 1. Contexto y Objetivo

El feature **Inventario** implementa las pantallas de consulta de niveles de stock, registro de movimientos (ENTRADA / SALIDA), visualización del historial Kardex y la capacidad de anular movimientos por parte de Supervisores. Es el núcleo operativo de ControlStock: toda variación de existencias se origina aquí.

**Objetivo de la etapa:**
- Implementar las páginas y componentes de inventario siguiendo TDD estricto (Red → Green → Refactor).
- El esquema Zod de cada entidad se escribe antes que el hook; el hook antes que el componente.
- Los escenarios E2E Playwright (ATDD) están escritos y fallando antes de integrar la funcionalidad.
- Conectar con `inventory-service` a través de Kong API Gateway en `http://<VPS_IP>:8000/api/v1`.

**Casos críticos:**
- Manejo del error 409 `STOCK_INSUFICIENTE` al registrar una SALIDA: el mensaje al usuario debe incluir el stock disponible actual extraído del cuerpo del error.
- Sincronización: tras registrar un movimiento exitoso, `useStock` y `useMovimientos` deben invalidarse automáticamente para reflejar el nuevo estado.
- SSR inicial en `/inventario/stock` (primera carga con datos del servidor), luego actualizaciones CSR vía TanStack Query.

---

## 2. Prerrequisitos

| Ítem | Detalle |
|------|---------|
| Etapa 4a completada | Scaffold Next.js 14 + App Router, providers QueryClient + SessionProvider configurados |
| Etapa 4b completada | Auth feature: NextAuth.js 4 + Keycloak OIDC, `middleware.ts`, `useSession()`, roles JWT |
| Etapa 4c completada | Feature Catálogo disponible: `useCategories()`, `catalogoSlice`, `EstadoBadge` |
| Variables de entorno | `NEXT_PUBLIC_API_URL` configurada |
| MSW v2 configurado | Handlers en `src/mocks/handlers/`, `server.ts` para Node, `browser.ts` para dev |
| Vitest + RTL | Configurados con `vitest.config.ts` y `setupTests.ts` |
| Playwright | `playwright.config.ts` apuntando a staging; datos seed disponibles |
| `inventarioSlice` | Se crea en esta etapa dentro del store Zustand global |

---

## 3. Rutas y Páginas

Todas las rutas viven bajo `src/app/(protected)/inventario/`.

| Ruta | Tipo | Archivo de Página | Componente de Página | Descripción |
|------|------|-------------------|----------------------|-------------|
| `/inventario` | Protegida (todos los roles) | `src/app/(protected)/inventario/page.tsx` | `InventarioPage` | Hub con panel de resumen: stock bajo mínimo count, últimos movimientos |
| `/inventario/stock` | Protegida (todos los roles) | `src/app/(protected)/inventario/stock/page.tsx` | `StockListPage` | Stock actual de todos los productos; SSR + CSR |
| `/inventario/movimientos` | Protegida (todos los roles) | `src/app/(protected)/inventario/movimientos/page.tsx` | `MovimientoListPage` | Historial paginado de movimientos con filtros |
| `/inventario/movimientos/nuevo` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/inventario/movimientos/nuevo/page.tsx` | `MovimientoFormPage` | Formulario de registro de movimiento |
| `/inventario/movimientos/[id]` | Protegida (todos los roles) | `src/app/(protected)/inventario/movimientos/[id]/page.tsx` | `MovimientoDetailPage` | Detalle de movimiento + botón anular |
| `/inventario/kardex/[productId]` | Protegida (todos los roles) | `src/app/(protected)/inventario/kardex/[productId]/page.tsx` | `KardexPage` | Kardex cronológico del producto |

### Protección de rutas

```typescript
// middleware.ts — reglas de inventario
const ROUTE_ROLES: Record<string, string[]> = {
  '/inventario/movimientos/nuevo': ['Operador', 'Supervisor', 'Administrador'],
};
// Anulación gestionada en componente (no ruta), solo rol Supervisor+ ve el botón.
```

---

## 4. Componentes

> **Nota TDD:** Crear el archivo de prueba → ejecutar `npm run test` (rojo) → implementar el mínimo código (verde) → refactorizar.

### 4.1 `StockTable`

**Archivo:** `src/features/inventario/components/StockTable.tsx`
**Prueba:** `src/features/inventario/components/__tests__/StockTable.test.tsx`

**Props:**
```typescript
interface StockTableProps {
  items: StockLevel[];
  isLoading?: boolean;
}
```

**Columnas:**
| Columna | Campo fuente | Notas |
|---------|-------------|-------|
| Código | `codigoProducto` | Monospace |
| Nombre | `nombreProducto` | — |
| Categoría | `nombreCategoria` | — |
| Stock Actual | `stockActual` | Negrita si `bajominimo` |
| Stock Mín. | `stockMinimo` | — |
| Stock Máx. | `stockMaximo` | — |
| Estado | `bajominimo` flag | Iconos: ⚠ rojo si bajo mínimo |

**Comportamiento:**
- Fila con clase `bg-red-50 border-l-4 border-red-500` cuando `item.bajominimo === true`.
- Estado de carga: skeleton de 10 filas.
- Estado vacío: "No se encontraron registros de stock."
- Enlace en nombre de producto → `/inventario/kardex/{productoId}`.

---

### 4.2 `StockFilters`

**Archivo:** `src/features/inventario/components/StockFilters.tsx`
**Prueba:** `src/features/inventario/components/__tests__/StockFilters.test.tsx`

**Props:**
```typescript
interface StockFiltersProps {
  onCategoriaChange: (categoriaId: string | null) => void;
  onBajominimoChange: (value: boolean) => void;
  categoriaValue: string | null;
  bajominimoValue: boolean;
}
```

**Campos:**
- `<select>` de categoría: opciones pobladas con `useCategorias()` del feature Catálogo.
- `<input type="checkbox">` "Solo productos bajo mínimo" — etiqueta con contador si `bajominimoValue` activo.

**Integración con `inventarioSlice`:** El componente padre `StockListPage` conecta las acciones `setCategoriaFilter` y `setBajominimo` del slice.

---

### 4.3 `MovimientoTable`

**Archivo:** `src/features/inventario/components/MovimientoTable.tsx`
**Prueba:** `src/features/inventario/components/__tests__/MovimientoTable.test.tsx`

**Props:**
```typescript
interface MovimientoTableProps {
  movimientos: Movimiento[];
  totalPages: number;
  currentPage: number;
  onPageChange: (page: number) => void;
  isLoading?: boolean;
}
```

**Columnas:**
| Columna | Campo fuente | Notas |
|---------|-------------|-------|
| Fecha | `fecha` | Formato `dd/MM/yyyy HH:mm` |
| Tipo | `tipo` | `<TipoBadge tipo={row.tipo} />` |
| Producto | `nombreProducto` | Enlace a `/inventario/kardex/{productoId}` |
| Cantidad | `cantidad` | Rojo si SALIDA, verde si ENTRADA |
| Saldo Resultante | `saldoResultante` | — |
| Referencia | `referenciaDocumento` | — |
| Estado | `estado` | PROCESADO / ANULADO (chip) |
| Acciones | — | Enlace a detalle |

---

### 4.4 `MovimientoForm`

**Archivo:** `src/features/inventario/components/MovimientoForm.tsx`
**Prueba:** `src/features/inventario/components/__tests__/MovimientoForm.test.tsx`

**Props:**
```typescript
interface MovimientoFormProps {
  onSuccess?: (movimientoId: string) => void;
}
```

**Campos:**
| Campo | Tipo | Validación |
|-------|------|-----------|
| `tipo` | `<select>` ENTRADA / SALIDA | Requerido |
| `productoId` | `<select>` buscable | Stock items de `useStock`; requerido; muestra código + nombre |
| `cantidad` | `<input type="number">` | > 0, entero |
| `referenciaDocumento` | `<input type="text">` | Requerido, mín 3, máx 100 |
| `fecha` | `<input type="date">` | Default hoy; requerido |

**Manejo de error 409:**
```typescript
// onError del hook useCreateMovimiento
onError: (error: ApiError) => {
  if (error.status === 409 && error.body?.error === 'STOCK_INSUFICIENTE') {
    setStockInsuficienteMessage(
      `Stock insuficiente. Stock disponible: ${error.body.stockDisponible}`
    );
  }
}
```
El mensaje se renderiza en un `<Alert variant="error" data-testid="stock-insuficiente-alert">`.

---

### 4.5 `KardexTable`

**Archivo:** `src/features/inventario/components/KardexTable.tsx`
**Prueba:** `src/features/inventario/components/__tests__/KardexTable.test.tsx`

**Props:**
```typescript
interface KardexTableProps {
  productId: string;
  entries: KardexEntrada[];
  stockActual: number;
  isLoading?: boolean;
}
```

**Sección encabezado:** Card de resumen con `stockActual`, `codigoProducto`, `nombreProducto`.

**Columnas de tabla:**
| Columna | Campo fuente |
|---------|-------------|
| Fecha | `fecha` |
| Tipo | `<TipoBadge tipo={row.tipo} />` |
| Referencia | `referenciaDocumento` |
| Cantidad | `cantidad` (con signo: +/−) |
| Saldo Resultante | `saldoResultante` |
| Estado | `estado` |

**Comportamiento:**
- Entradas ordenadas cronológicamente ascendente.
- Estado vacío: "No hay movimientos registrados para este producto."

---

### 4.6 `AnularMovimientoModal`

**Archivo:** `src/features/inventario/components/AnularMovimientoModal.tsx`
**Prueba:** `src/features/inventario/components/__tests__/AnularMovimientoModal.test.tsx`

**Props:**
```typescript
interface AnularMovimientoModalProps {
  open: boolean;
  movimientoId: string;
  referenciaDocumento: string;
  onConfirm: () => void;
  onCancel: () => void;
  isLoading?: boolean;
}
```

**Comportamiento:**
- Solo Supervisor y Administrador pueden ver el botón "Anular" en `MovimientoDetailPage`.
- Modal con mensaje: `¿Confirmar anulación del movimiento "${referenciaDocumento}"? Esta acción es irreversible.`
- Botón "Anular" deshabilita durante `isLoading`.

---

### 4.7 `TipoBadge`

**Archivo:** `src/features/inventario/components/TipoBadge.tsx`
**Prueba:** `src/features/inventario/components/__tests__/TipoBadge.test.tsx`

**Props:**
```typescript
interface TipoBadgeProps {
  tipo: 'ENTRADA' | 'SALIDA' | 'AJUSTE';
}
```

**Colores:**
| Tipo | Clases CSS | Texto |
|------|-----------|-------|
| `ENTRADA` | `bg-green-100 text-green-800` | "ENTRADA" |
| `SALIDA` | `bg-red-100 text-red-800` | "SALIDA" |
| `AJUSTE` | `bg-blue-100 text-blue-800` | "AJUSTE" |

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** MSW handler + prueba del hook creados antes de implementar el hook.

Todos los hooks residen en `src/features/inventario/hooks/`.

### 5.1 `useStock`

```typescript
// src/features/inventario/hooks/useStock.ts
export function useStock(params?: StockParams) {
  return useQuery({
    queryKey: ['stock', params],
    queryFn: () => fetchStock(params),
    staleTime: 30 * 1000, // 30 segundos — stock cambia con frecuencia
  });
}
```

- **Endpoint:** `GET /inventory/stock`
- **Query params:** `{ categoriaId?: string, bajominimo?: boolean }`
- **staleTime:** 30 segundos (los niveles de stock cambian con movimientos frecuentes).

---

### 5.2 `useStockByProducto`

```typescript
export function useStockByProducto(productId: string) {
  return useQuery({
    queryKey: ['stock', 'producto', productId],
    queryFn: () => fetchStockByProductId(productId),
    enabled: !!productId,
    staleTime: 30 * 1000,
  });
}
```

- **Endpoint:** `GET /inventory/stock/{productId}`
- Usado en `KardexPage` header y `ProductoDetail` del feature catálogo.

---

### 5.3 `useMovimientos`

```typescript
export function useMovimientos(params: MovimientosParams) {
  return useQuery({
    queryKey: ['movimientos', params],
    queryFn: () => fetchMovimientos(params),
    staleTime: 30 * 1000,
  });
}
```

- **Endpoint:** `GET /inventory/movements`
- **Query params:** `{ productoId?: string, tipo?: 'ENTRADA'|'SALIDA', page: number, size: number }`

---

### 5.4 `useCreateMovimiento`

```typescript
export function useCreateMovimiento() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateMovimientoInput) => createMovimiento(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['stock'] });
      queryClient.invalidateQueries({ queryKey: ['movimientos'] });
    },
    // El manejo del 409 queda en el onError del componente
    // o se puede lanzar como error tipado desde mutationFn
  });
}
```

- **Endpoint:** `POST /inventory/movements`
- **Error 409:** El `mutationFn` debe relanzar el error con el cuerpo parseado:
  ```typescript
  if (response.status === 409) {
    const body = await response.json();
    throw new StockInsuficienteError(body); // clase custom con stockDisponible
  }
  ```

---

### 5.5 `useAnularMovimiento`

```typescript
export function useAnularMovimiento(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => anularMovimiento(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['movimientos'] });
      queryClient.invalidateQueries({ queryKey: ['movimientos', id] });
      queryClient.invalidateQueries({ queryKey: ['stock'] });
    },
  });
}
```

- **Endpoint:** `POST /inventory/movements/{id}/anular`

---

### 5.6 `useKardex`

```typescript
export function useKardex(productId: string) {
  return useQuery({
    queryKey: ['kardex', productId],
    queryFn: () => fetchKardex(productId),
    enabled: !!productId,
    staleTime: 60 * 1000,
  });
}
```

- **Endpoint:** `GET /inventory/kardex/{productId}`

---

## 6. Estado Global (Zustand)

> **Nota TDD:** Pruebas del slice escritas antes de la implementación. Verificar cada acción.

**Archivo:** `src/store/slices/inventarioSlice.ts`

```typescript
interface InventarioState {
  bajominimoFilter: boolean;
  categoriaFilter: string | null;
  setBajominimo: (value: boolean) => void;
  setCategoriaFilter: (categoriaId: string | null) => void;
}

export const useInventarioSlice = (set: SetState<InventarioState>): InventarioState => ({
  bajominimoFilter: false,
  categoriaFilter:  null,
  setBajominimo:     (value) => set({ bajominimoFilter: value }),
  setCategoriaFilter:(categoriaId) => set({ categoriaFilter: categoriaId }),
});
```

**Integración con `StockListPage`:**
```typescript
const { bajominimoFilter, categoriaFilter, setBajominimo, setCategoriaFilter } = useInventarioStore();
const { data: stockData, isLoading } = useStock({
  categoriaId: categoriaFilter ?? undefined,
  bajominimo:  bajominimoFilter || undefined,
});
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** Cada schema tiene su prueba unitaria creada antes de la definición del schema.

**Archivo:** `src/features/inventario/schemas/movimiento.schema.ts`

```typescript
import { z } from 'zod';

export const CreateMovimientoSchema = z.object({
  tipo: z.enum(['ENTRADA', 'SALIDA'], {
    errorMap: () => ({ message: 'Tipo de movimiento inválido' }),
  }),
  productoId: z.string().uuid('Debe seleccionar un producto válido'),
  cantidad: z
    .number({ invalid_type_error: 'Ingrese un número' })
    .positive('Cantidad debe ser mayor a 0')
    .int('La cantidad debe ser un número entero'),
  referenciaDocumento: z
    .string()
    .min(3, 'Mínimo 3 caracteres')
    .max(100, 'Máximo 100 caracteres'),
  fecha: z.string().date('Fecha inválida'),
});

export type CreateMovimientoInput = z.infer<typeof CreateMovimientoSchema>;
```

---

**Archivo:** `src/features/inventario/schemas/stock.schema.ts`

```typescript
import { z } from 'zod';

export const StockLevelResponseSchema = z.object({
  productoId:      z.string().uuid(),
  codigoProducto:  z.string(),
  nombreProducto:  z.string(),
  categoriaId:     z.string().uuid(),
  nombreCategoria: z.string(),
  stockActual:     z.number(),
  stockMinimo:     z.number(),
  stockMaximo:     z.number(),
  bajominimo:      z.boolean(),
  updatedAt:       z.string().datetime(),
});

export const StockInsuficienteErrorSchema = z.object({
  error:           z.literal('STOCK_INSUFICIENTE'),
  stockDisponible: z.number(),
  productoId:      z.string().uuid(),
});

export type StockLevel           = z.infer<typeof StockLevelResponseSchema>;
export type StockInsuficienteError = z.infer<typeof StockInsuficienteErrorSchema>;
```

---

**Archivo:** `src/features/inventario/schemas/kardex.schema.ts`

```typescript
import { z } from 'zod';

export const KardexEntradaSchema = z.object({
  movimientoId:        z.string().uuid(),
  tipo:                z.enum(['ENTRADA', 'SALIDA', 'AJUSTE']),
  cantidad:            z.number(),
  referenciaDocumento: z.string(),
  fecha:               z.string().datetime(),
  saldoResultante:     z.number(),
  estado:              z.enum(['PROCESADO', 'ANULADO']),
});

export const KardexResponseSchema = z.object({
  productoId:      z.string().uuid(),
  codigoProducto:  z.string(),
  nombreProducto:  z.string(),
  stockActual:     z.number(),
  entradas:        z.array(KardexEntradaSchema),
});

export type KardexEntrada  = z.infer<typeof KardexEntradaSchema>;
export type KardexResponse = z.infer<typeof KardexResponseSchema>;
```

---

## 8. Autenticación y Autorización

### 8.1 Tabla de permisos por acción en Inventario

| Acción | Operador | Supervisor | Administrador | Gerente | Analista | Auditor |
|--------|----------|-----------|---------------|---------|----------|---------|
| Ver stock | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ver movimientos | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Registrar movimiento | ✓ | ✓ | ✓ | — | — | — |
| Anular movimiento | — | ✓ | ✓ | — | — | — |
| Ver Kardex | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

### 8.2 Implementación de control de acceso

```typescript
// MovimientoDetailPage
const roles = useRol();
const puedeAnular = tieneRol(roles, 'Supervisor', 'Administrador');

// Ruta /inventario/movimientos/nuevo
// Protegida por middleware.ts → redirige a /no-autorizado si no es Operador+
```

### 8.3 Token JWT

El header `Authorization: Bearer <token>` se adjunta automáticamente mediante el interceptor de fetch configurado en el cliente API base (`src/lib/apiClient.ts`), que lee el token de la sesión NextAuth en el contexto de cliente, o del cookie de sesión en contexto de servidor.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Regla Red-Green-Refactor:** Test fallido → mínima implementación → refactor.

### 9.1 Pruebas de Esquema `CreateMovimientoSchema`

**Archivo:** `src/features/inventario/schemas/__tests__/movimiento.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { CreateMovimientoSchema } from '../movimiento.schema';

describe('CreateMovimientoSchema', () => {
  const validEntrada = {
    tipo:                'ENTRADA',
    productoId:          'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    cantidad:            30,
    referenciaDocumento: 'OC-2025-001',
    fecha:               '2025-06-01',
  } as const;

  const validSalida = { ...validEntrada, tipo: 'SALIDA' as const };

  it('debería pasar con ENTRADA válida', () => {
    expect(CreateMovimientoSchema.safeParse(validEntrada).success).toBe(true);
  });

  it('debería pasar con SALIDA válida', () => {
    expect(CreateMovimientoSchema.safeParse(validSalida).success).toBe(true);
  });

  it('debería fallar cuando cantidad = 0', () => {
    const result = CreateMovimientoSchema.safeParse({ ...validEntrada, cantidad: 0 });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('cantidad');
    expect(result.error?.issues[0].message).toBe('Cantidad debe ser mayor a 0');
  });

  it('debería fallar cuando cantidad = -1', () => {
    const result = CreateMovimientoSchema.safeParse({ ...validEntrada, cantidad: -1 });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('cantidad');
  });

  it('debería fallar si referenciaDocumento está ausente', () => {
    const { referenciaDocumento, ...sinRef } = validEntrada;
    const result = CreateMovimientoSchema.safeParse(sinRef);
    expect(result.success).toBe(false);
  });

  it('debería fallar si referenciaDocumento tiene menos de 3 caracteres', () => {
    const result = CreateMovimientoSchema.safeParse({ ...validEntrada, referenciaDocumento: 'AB' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].message).toContain('Mínimo 3 caracteres');
  });

  it('debería fallar con tipo inválido', () => {
    const result = CreateMovimientoSchema.safeParse({ ...validEntrada, tipo: 'TRANSFERENCIA' });
    expect(result.success).toBe(false);
  });

  it('debería fallar si fecha no tiene formato YYYY-MM-DD', () => {
    const result = CreateMovimientoSchema.safeParse({ ...validEntrada, fecha: '01/06/2025' });
    expect(result.success).toBe(false);
  });
});
```

---

### 9.2 Pruebas del hook `useCreateMovimiento`

**Archivo:** `src/features/inventario/hooks/__tests__/useCreateMovimiento.test.tsx`

MSW handlers:

```typescript
// src/mocks/handlers/inventory.ts
import { http, HttpResponse } from 'msw';

export const inventoryHandlers = [
  http.get('/api/v1/inventory/stock', () =>
    HttpResponse.json([
      {
        productoId: 'prod-uuid-1', codigoProducto: 'P001', nombreProducto: 'Aceite',
        categoriaId: 'cat-1', nombreCategoria: 'Lubricantes',
        stockActual: 50, stockMinimo: 10, stockMaximo: 200, bajominimo: false,
        updatedAt: '2025-06-01T00:00:00Z',
      },
    ])
  ),
  http.post('/api/v1/inventory/movements', () =>
    HttpResponse.json(
      { id: 'mov-uuid-1', tipo: 'ENTRADA', productoId: 'prod-uuid-1', cantidad: 30,
        referenciaDocumento: 'OC-001', fecha: '2025-06-01', saldoResultante: 80,
        estado: 'PROCESADO', createdAt: '2025-06-01T10:00:00Z' },
      { status: 201 }
    )
  ),
];
```

```typescript
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useCreateMovimiento } from '../useCreateMovimiento';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

describe('useCreateMovimiento', () => {
  const validPayload = {
    tipo:                'ENTRADA' as const,
    productoId:          'prod-uuid-1',
    cantidad:            30,
    referenciaDocumento: 'OC-001',
    fecha:               '2025-06-01',
  };

  it('éxito: invalida queries de stock y movimientos', async () => {
    const { result } = renderHook(() => useCreateMovimiento(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    // La invalidación se verifica indirectamente: el queryClient.invalidateQueries fue llamado
    // Se puede espiar queryClient con vi.spyOn en el wrapper
  });

  it('error 409 STOCK_INSUFICIENTE: retorna stockDisponible en el error', async () => {
    server.use(
      http.post('/api/v1/inventory/movements', () =>
        HttpResponse.json(
          { error: 'STOCK_INSUFICIENTE', stockDisponible: 15, productoId: 'prod-uuid-1' },
          { status: 409 }
        )
      )
    );
    const { result } = renderHook(() => useCreateMovimiento(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate({ ...validPayload, tipo: 'SALIDA', cantidad: 100 }); });
    await waitFor(() => expect(result.current.isError).toBe(true));
    // El error debe exponer stockDisponible
    const error = result.current.error as any;
    expect(error?.stockDisponible).toBe(15);
  });

  it('error 400: la mutación queda en estado error con mensaje de validación', async () => {
    server.use(
      http.post('/api/v1/inventory/movements', () =>
        HttpResponse.json({ message: 'Producto no encontrado' }, { status: 400 })
      )
    );
    const { result } = renderHook(() => useCreateMovimiento(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

---

### 9.3 Pruebas del componente `MovimientoForm`

**Archivo:** `src/features/inventario/components/__tests__/MovimientoForm.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MovimientoForm } from '../MovimientoForm';

vi.mock('@/features/inventario/hooks/useStock', () => ({
  useStock: () => ({
    data: [
      { productoId: 'prod-uuid-1', codigoProducto: 'P001', nombreProducto: 'Aceite',
        stockActual: 50, bajominimo: false },
    ],
    isLoading: false,
  }),
}));

vi.mock('@/features/inventario/hooks/useCreateMovimiento', () => ({
  useCreateMovimiento: () => ({
    mutate: vi.fn(),
    isPending: false,
    isError: false,
    error: null,
  }),
}));

describe('MovimientoForm', () => {
  it('debería renderizar el selector de tipo', () => {
    render(<MovimientoForm />);
    expect(screen.getByLabelText(/tipo/i)).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /entrada/i })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /salida/i })).toBeInTheDocument();
  });

  it('debería renderizar el selector de producto', () => {
    render(<MovimientoForm />);
    expect(screen.getByLabelText(/producto/i)).toBeInTheDocument();
  });

  it('debería renderizar el input de cantidad', () => {
    render(<MovimientoForm />);
    expect(screen.getByLabelText(/cantidad/i)).toBeInTheDocument();
  });

  it('debería llamar la mutación al enviar el formulario con datos válidos', async () => {
    const mockMutate = vi.fn();
    vi.mocked(
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      require('@/features/inventario/hooks/useCreateMovimiento').useCreateMovimiento
    ).mockReturnValue({ mutate: mockMutate, isPending: false, isError: false, error: null });

    const user = userEvent.setup();
    render(<MovimientoForm />);
    await user.selectOptions(screen.getByLabelText(/tipo/i), 'ENTRADA');
    await user.selectOptions(screen.getByLabelText(/producto/i), 'prod-uuid-1');
    await user.type(screen.getByLabelText(/cantidad/i), '30');
    await user.type(screen.getByLabelText(/referencia/i), 'OC-2025-001');
    await user.click(screen.getByRole('button', { name: /registrar/i }));
    await waitFor(() => expect(mockMutate).toHaveBeenCalled());
  });

  it('debería mostrar alerta "Stock disponible: X" cuando error es 409', () => {
    vi.mock('@/features/inventario/hooks/useCreateMovimiento', () => ({
      useCreateMovimiento: () => ({
        mutate: vi.fn(),
        isPending: false,
        isError: true,
        error: { stockDisponible: 15, error: 'STOCK_INSUFICIENTE' },
      }),
    }));
    render(<MovimientoForm />);
    expect(screen.getByTestId('stock-insuficiente-alert')).toBeInTheDocument();
    expect(screen.getByText(/stock disponible: 15/i)).toBeInTheDocument();
  });
});
```

---

### 9.4 Pruebas del componente `KardexTable`

**Archivo:** `src/features/inventario/components/__tests__/KardexTable.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { KardexTable } from '../KardexTable';
import type { KardexEntrada } from '../../../schemas/kardex.schema';

const mockEntries: KardexEntrada[] = [
  { movimientoId: 'mov-1', tipo: 'ENTRADA', cantidad: 100, referenciaDocumento: 'OC-001',
    fecha: '2025-01-01T08:00:00Z', saldoResultante: 100, estado: 'PROCESADO' },
  { movimientoId: 'mov-2', tipo: 'SALIDA', cantidad: 30, referenciaDocumento: 'VENTA-001',
    fecha: '2025-01-02T10:00:00Z', saldoResultante: 70, estado: 'PROCESADO' },
  { movimientoId: 'mov-3', tipo: 'ENTRADA', cantidad: 50, referenciaDocumento: 'OC-002',
    fecha: '2025-01-03T09:00:00Z', saldoResultante: 120, estado: 'PROCESADO' },
];

describe('KardexTable', () => {
  it('debería renderizar las entradas en orden cronológico', () => {
    render(<KardexTable productId="prod-1" entries={mockEntries} stockActual={120} />);
    const rows = screen.getAllByRole('row');
    // rows[0] = encabezado, rows[1..3] = datos
    expect(rows).toHaveLength(4); // 1 header + 3 data
    // Verificar orden por fecha
    expect(rows[1]).toHaveTextContent('OC-001');
    expect(rows[2]).toHaveTextContent('VENTA-001');
    expect(rows[3]).toHaveTextContent('OC-002');
  });

  it('debería mostrar el saldoResultante en cada fila', () => {
    render(<KardexTable productId="prod-1" entries={mockEntries} stockActual={120} />);
    expect(screen.getByText('100')).toBeInTheDocument();
    expect(screen.getByText('70')).toBeInTheDocument();
    expect(screen.getByText('120')).toBeInTheDocument();
  });

  it('debería mostrar mensaje de estado vacío cuando entries es []', () => {
    render(<KardexTable productId="prod-1" entries={[]} stockActual={0} />);
    expect(screen.getByText(/no hay movimientos registrados/i)).toBeInTheDocument();
  });

  it('debería mostrar el stockActual en el card de resumen', () => {
    render(<KardexTable productId="prod-1" entries={mockEntries} stockActual={120} />);
    expect(screen.getByText('120')).toBeInTheDocument();
  });
});
```

---

### 9.5 Pruebas del componente `TipoBadge`

**Archivo:** `src/features/inventario/components/__tests__/TipoBadge.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { TipoBadge } from '../TipoBadge';

describe('TipoBadge', () => {
  it('ENTRADA → badge verde', () => {
    render(<TipoBadge tipo="ENTRADA" />);
    const badge = screen.getByText('ENTRADA');
    expect(badge).toHaveClass('bg-green-100');
    expect(badge).toHaveClass('text-green-800');
  });

  it('SALIDA → badge rojo', () => {
    render(<TipoBadge tipo="SALIDA" />);
    const badge = screen.getByText('SALIDA');
    expect(badge).toHaveClass('bg-red-100');
    expect(badge).toHaveClass('text-red-800');
  });

  it('AJUSTE → badge azul', () => {
    render(<TipoBadge tipo="AJUSTE" />);
    const badge = screen.getByText('AJUSTE');
    expect(badge).toHaveClass('bg-blue-100');
    expect(badge).toHaveClass('text-blue-800');
  });
});
```

---

### 9.6 Pruebas del `inventarioSlice`

**Archivo:** `src/store/slices/__tests__/inventarioSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { act } from '@testing-library/react';
import { create } from 'zustand';
import { useInventarioSlice } from '../inventarioSlice';

const useTestStore = create(useInventarioSlice);

describe('inventarioSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ bajominimoFilter: false, categoriaFilter: null });
  });

  it('estado inicial correcto', () => {
    const state = useTestStore.getState();
    expect(state.bajominimoFilter).toBe(false);
    expect(state.categoriaFilter).toBeNull();
  });

  it('setBajominimo: cambia a true', () => {
    act(() => { useTestStore.getState().setBajominimo(true); });
    expect(useTestStore.getState().bajominimoFilter).toBe(true);
  });

  it('setBajominimo: puede volver a false', () => {
    act(() => {
      useTestStore.getState().setBajominimo(true);
      useTestStore.getState().setBajominimo(false);
    });
    expect(useTestStore.getState().bajominimoFilter).toBe(false);
  });

  it('setCategoriaFilter: actualiza el filtro de categoría', () => {
    act(() => { useTestStore.getState().setCategoriaFilter('cat-uuid-1'); });
    expect(useTestStore.getState().categoriaFilter).toBe('cat-uuid-1');
  });

  it('setCategoriaFilter: puede resetear a null', () => {
    act(() => {
      useTestStore.getState().setCategoriaFilter('cat-uuid-1');
      useTestStore.getState().setCategoriaFilter(null);
    });
    expect(useTestStore.getState().categoriaFilter).toBeNull();
  });

  it('setBajominimo y setCategoriaFilter son independientes', () => {
    act(() => {
      useTestStore.getState().setBajominimo(true);
      useTestStore.getState().setCategoriaFilter('cat-uuid-2');
    });
    const state = useTestStore.getState();
    expect(state.bajominimoFilter).toBe(true);
    expect(state.categoriaFilter).toBe('cat-uuid-2');
  });
});
```

---

## 10. Pruebas E2E (Playwright, ATDD)

> **Principio ATDD:** Los escenarios se escriben antes de que el feature esté integrado. Se ejecutan en staging con datos seed predeterminados.

**Archivo:** `e2e/inventario/inventario.spec.ts`

### Datos seed requeridos en staging

```yaml
# seed-inventario.yml
productos:
  - id: "prod-seed-inv-01"
    codigo: "INV-SEED-01"
    nombre: "Aceite Motor Seed"
    categoriaId: "cat-seed-01"
    stockMinimo: 10
    stockMaximo: 200

stock:
  - productoId: "prod-seed-inv-01"
    stockActual: 50
```

---

### TC-INV-01: Registrar ENTRADA y verificar aumento de stock

```typescript
test('TC-INV-01: Registrar ENTRADA de 30 unidades incrementa el stock en 30', async ({ page }) => {
  // GIVEN: Stock inicial = 50 unidades para INV-SEED-01
  await page.goto('/inventario/stock');
  const stockInicial = await page.locator('[data-testid="stock-INV-SEED-01"]').textContent();
  expect(Number(stockInicial)).toBe(50);

  // WHEN: Registra un movimiento de ENTRADA
  await page.goto('/inventario/movimientos/nuevo');
  await page.getByLabel(/tipo/i).selectOption('ENTRADA');
  await page.getByLabel(/producto/i).selectOption('INV-SEED-01');
  await page.getByLabel(/cantidad/i).fill('30');
  await page.getByLabel(/referencia/i).fill('E2E-OC-001');
  await page.getByRole('button', { name: /registrar/i }).click();

  // THEN: Redirige al detalle o lista de movimientos
  await expect(page).toHaveURL(/\/inventario\/movimientos/);

  // AND: El stock aumenta en 30
  await page.goto('/inventario/stock');
  const stockNuevo = await page.locator('[data-testid="stock-INV-SEED-01"]').textContent();
  expect(Number(stockNuevo)).toBe(80);
});
```

---

### TC-INV-02: SALIDA con cantidad mayor al stock disponible → error 409

```typescript
test('TC-INV-02: SALIDA con cantidad > stock muestra error de stock insuficiente', async ({ page }) => {
  // GIVEN: Stock actual = 50 para INV-SEED-01
  await page.goto('/inventario/movimientos/nuevo');

  // WHEN: Intenta registrar SALIDA de 200 unidades (> 50 disponibles)
  await page.getByLabel(/tipo/i).selectOption('SALIDA');
  await page.getByLabel(/producto/i).selectOption('INV-SEED-01');
  await page.getByLabel(/cantidad/i).fill('200');
  await page.getByLabel(/referencia/i).fill('E2E-VENTA-FAIL');
  await page.getByRole('button', { name: /registrar/i }).click();

  // THEN: Aparece alerta de stock insuficiente con el stock disponible
  await expect(page.getByTestId('stock-insuficiente-alert')).toBeVisible();
  await expect(page.getByText(/stock disponible:/i)).toBeVisible();
  // El número en el mensaje debe ser <= 50
  const alertText = await page.getByTestId('stock-insuficiente-alert').textContent();
  expect(alertText).toMatch(/stock disponible: \d+/i);

  // AND: El formulario NO fue enviado (permanece en la página)
  await expect(page).toHaveURL('/inventario/movimientos/nuevo');
});
```

---

### TC-INV-03: Kardex cronológico con saldoResultante correcto

```typescript
test('TC-INV-03: Kardex muestra entradas en orden cronológico con saldo correcto', async ({ page }) => {
  // GIVEN: Producto con historial de movimientos seed
  await page.goto('/inventario/kardex/prod-seed-inv-01');

  // THEN: El Kardex carga y muestra entradas
  await expect(page.getByRole('heading', { name: /kardex/i })).toBeVisible();

  const rows = page.getByRole('row');
  // Debe haber al menos 2 filas (header + 1 movimiento de seed)
  await expect(rows).toHaveCount({ min: 2 });

  // Verificar orden cronológico: la primera entrada de datos debe ser la más antigua
  // (seed tiene movimiento de '2025-01-01' antes del de '2025-01-02')
  const firstDataRow = rows.nth(1);
  const lastDataRow  = rows.last();
  const firstFecha   = await firstDataRow.locator('[data-col="fecha"]').textContent();
  const lastFecha    = await lastDataRow.locator('[data-col="fecha"]').textContent();
  expect(new Date(firstFecha!).getTime()).toBeLessThanOrEqual(new Date(lastFecha!).getTime());

  // Verificar que la columna saldoResultante existe y tiene valores numéricos
  const saldos = await page.locator('[data-col="saldoResultante"]').allTextContents();
  saldos.forEach((s) => expect(Number(s)).toBeGreaterThanOrEqual(0));
});
```

---

### TC-INV-04: Supervisor anula un movimiento

```typescript
test('TC-INV-04: Supervisor anula un movimiento y aparece como ANULADO en la lista', async ({ page }) => {
  // GIVEN: Movimiento PROCESADO existente en seed
  await page.goto('/inventario/movimientos');
  await expect(page.getByText('E2E-SEED-MOV-01')).toBeVisible();

  // WHEN: Abre el detalle del movimiento
  await page.getByRole('link', { name: 'E2E-SEED-MOV-01' }).click();
  await expect(page).toHaveURL(/\/inventario\/movimientos\/[a-z0-9-]+/);

  // AND: Click en "Anular"
  await page.getByRole('button', { name: /anular/i }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: /confirmar/i }).click();

  // THEN: Regresa a la lista, el movimiento aparece como ANULADO
  await page.goto('/inventario/movimientos');
  const row = page.getByRole('row', { name: /E2E-SEED-MOV-01/i });
  await expect(row.getByText('ANULADO')).toBeVisible();
});
```

---

## 11. Criterios de Aceptación

### 11.1 Criterios funcionales

| ID | Criterio | Verificación |
|----|---------|-------------|
| CA-INV-01 | Operador puede registrar movimientos ENTRADA y SALIDA | E2E TC-INV-01 + test unitario `useCreateMovimiento` |
| CA-INV-02 | SALIDA con stock insuficiente muestra error 409 con stock disponible | E2E TC-INV-02 + test unitario hook |
| CA-INV-03 | Kardex muestra historial cronológico con saldoResultante correcto | E2E TC-INV-03 + test `KardexTable` |
| CA-INV-04 | Supervisor puede anular movimiento; queda como ANULADO | E2E TC-INV-04 |
| CA-INV-05 | Operador NO tiene botón "Anular" visible | Test unitario `MovimientoDetailPage` con mock de rol |
| CA-INV-06 | Filas con `bajominimo=true` se destacan visualmente en rojo | Test unitario `StockTable` |
| CA-INV-07 | Filtros de stock (categoría + bajominimo) actualizan la lista | Test unitario `inventarioSlice` + integración |
| CA-INV-08 | Tras registrar movimiento, stock se actualiza sin recarga manual | Test `useCreateMovimiento` → invalidación |

### 11.2 Criterios de calidad TDD

| Criterio | Evidencia requerida |
|---------|-------------------|
| Schemas Zod tienen prueba fallida antes de implementación | Commit de test antes que schema |
| Hooks tienen MSW handler + prueba antes de implementación | Commit de handler + test antes que hook |
| Componentes tienen prueba antes de implementación | Commit de test antes que componente |
| `npm run test` verde al finalizar la etapa | Output de CI sin fallos |
| E2E Playwright pasan en staging (TC-INV-01 al TC-INV-04) | Reporte Playwright sin errores |
| Cobertura de ramas > 80% en feature inventario | Reporte Vitest coverage |

### 11.3 Criterios de integración

| Criterio | Detalle |
|---------|---------|
| SSR en `/inventario/stock` | Primera carga con datos del servidor (sin flash de loading) |
| Invalidación cruzada de caché | Al crear movimiento: `['stock']` y `['movimientos']` se refrescan |
| Error 409 parseado correctamente | `stockDisponible` extraído del body y mostrado al usuario |
| Auth token incluido en todas las llamadas | Verificado con herramientas de red en staging |
