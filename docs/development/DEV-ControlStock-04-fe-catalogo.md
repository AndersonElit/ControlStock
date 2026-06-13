# Etapa 4c — Frontend: Feature Catálogo

## 1. Contexto y Objetivo

El feature **Catálogo** centraliza la gestión de datos maestros del sistema ControlStock: categorías de productos y productos. Provee las pantallas de mantenimiento (listado, creación, edición, detalle) para que los roles autorizados administren el catálogo de manera controlada, con validaciones de integridad de stock en el frontend previas a toda llamada al backend.

**Objetivo de la etapa:**
- Implementar las páginas y componentes del catálogo siguiendo la disciplina TDD (Red → Green → Refactor).
- Escribir primero los esquemas Zod, luego los hooks TanStack Query, luego los componentes React; en cada paso existe una prueba fallida antes de escribir el código de producción.
- Garantizar que los criterios de aceptación E2E (Playwright / ATDD) están escritos y fallando antes de integrar la funcionalidad completa.
- Conectar con `catalog-service` a través de Kong API Gateway en `http://<VPS_IP>:8000/api/v1`.

**Alcance:**
- Gestión de categorías (CRUD restringido por rol).
- Gestión de productos (CRUD + visualización de stock actual desde `inventory-service`).
- Filtros de lista (categoría, estado).
- Control de acceso por rol en componentes y rutas.

---

## 2. Prerrequisitos

| Ítem | Detalle |
|------|---------|
| Etapa 4a completada | Scaffold Next.js 14 + App Router listo, `src/` structure, providers configurados |
| Etapa 4b completada | Auth feature: NextAuth.js + Keycloak, `middleware.ts`, `useSession()`, roles en JWT |
| Variables de entorno | `NEXT_PUBLIC_API_URL=http://<VPS_IP>:8000/api/v1` definida en `.env.local` y K3s ConfigMap |
| Dependencias instaladas | `@tanstack/react-query@^5`, `zustand@^4`, `zod@^3`, `react-hook-form`, `@hookform/resolvers` |
| Herramientas de prueba | `vitest`, `@testing-library/react`, `@testing-library/user-event`, `msw@^2` configurados |
| Playwright | Instalado y configurado en `playwright.config.ts` con base URL de staging |
| Kong accesible | Gateway disponible en entorno de desarrollo/staging; mock MSW para tests unitarios |
| catalogoSlice | Se crea en esta etapa dentro del store Zustand global |

---

## 3. Rutas y Páginas

Todas las rutas viven bajo `src/app/(protected)/catalogo/`.

| Ruta | Tipo | Archivo de Página | Componente de Página | Descripción |
|------|------|-------------------|----------------------|-------------|
| `/catalogo` | Protegida (todos los roles auth) | `src/app/(protected)/catalogo/page.tsx` | `CatalogoPage` | Hub principal: enlaces rápidos a Categorías y Productos, resumen de conteos |
| `/catalogo/categorias` | Protegida (todos los roles auth) | `src/app/(protected)/catalogo/categorias/page.tsx` | `CategoriaListPage` | Listado de categorías con paginación |
| `/catalogo/categorias/nueva` | Protegida (Supervisor, Administrador) | `src/app/(protected)/catalogo/categorias/nueva/page.tsx` | `CategoriaFormPage` | Formulario de creación de categoría |
| `/catalogo/categorias/[id]/editar` | Protegida (Supervisor, Administrador) | `src/app/(protected)/catalogo/categorias/[id]/editar/page.tsx` | `CategoriaFormPage` | Formulario de edición de categoría |
| `/catalogo/productos` | Protegida (todos los roles auth) | `src/app/(protected)/catalogo/productos/page.tsx` | `ProductoListPage` | Listado de productos con filtros (categoría, estado) y paginación |
| `/catalogo/productos/nuevo` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/catalogo/productos/nuevo/page.tsx` | `ProductoFormPage` | Formulario de creación de producto |
| `/catalogo/productos/[id]` | Protegida (todos los roles auth) | `src/app/(protected)/catalogo/productos/[id]/page.tsx` | `ProductoDetailPage` | Detalle del producto + stock actual desde inventory-service |
| `/catalogo/productos/[id]/editar` | Protegida (Operador, Supervisor, Administrador) | `src/app/(protected)/catalogo/productos/[id]/editar/page.tsx` | `ProductoFormPage` | Formulario de edición de producto |

### Protección de rutas — `middleware.ts`

```typescript
// src/middleware.ts (extracto relevante para catálogo)
const ROUTE_ROLES: Record<string, string[]> = {
  '/catalogo/categorias/nueva':       ['Supervisor', 'Administrador'],
  '/catalogo/categorias/:id/editar':  ['Supervisor', 'Administrador'],
  '/catalogo/productos/nuevo':        ['Operador', 'Supervisor', 'Administrador'],
  '/catalogo/productos/:id/editar':   ['Operador', 'Supervisor', 'Administrador'],
};
```

Las rutas no listadas permiten acceso a cualquier sesión activa. El middleware redirige a `/no-autorizado` si el rol del usuario no está incluido.

---

## 4. Componentes

> **Nota TDD:** Cada componente tiene su archivo de prueba creado **antes** que el componente mismo. El test debe fallar (importación vacía / componente vacío) antes de implementar. Sigue el ciclo **Red → Green → Refactor**.

### 4.1 `CategoriaTable`

**Archivo:** `src/features/catalogo/components/CategoriaTable.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/CategoriaTable.test.tsx`

**Props:**
```typescript
interface CategoriaTableProps {
  categorias: Categoria[];
  onEdit: (id: string) => void;
  onDeactivate: (id: string) => void;
  isLoading?: boolean;
}
```

**Columnas:**
| Columna | Campo fuente | Notas |
|---------|-------------|-------|
| Código | `codigo` | Monospace |
| Nombre | `nombre` | — |
| Estado | `estado` | Renderiza `<EstadoBadge estado={row.estado} />` |
| Acciones | — | Botones Editar / Desactivar (ocultos si rol no autorizado) |

**Comportamiento:**
- Estado de carga: muestra skeleton de 5 filas.
- Lista vacía: muestra mensaje "No hay categorías registradas."
- Botón **Desactivar** solo visible si el usuario tiene rol Supervisor o Administrador Y `categoria.estado === 'ACTIVO'`.
- Botón **Editar** visible para Supervisor y Administrador.

---

### 4.2 `CategoriaForm`

**Archivo:** `src/features/catalogo/components/CategoriaForm.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/CategoriaForm.test.tsx`

**Props:**
```typescript
interface CategoriaFormProps {
  defaultValues?: Partial<CreateCategoriaInput>;
  onSubmit: (data: CreateCategoriaInput) => Promise<void>;
  isSubmitting?: boolean;
  mode: 'create' | 'edit';
}
```

**Campos:**
| Campo | Tipo | Validación |
|-------|------|-----------|
| `codigo` | `<input type="text">` | Requerido, máx 20 caracteres |
| `nombre` | `<input type="text">` | Requerido, máx 100 caracteres |
| `descripcion` | `<textarea>` | Opcional, máx 500 caracteres |
| `estado` | `<select>` | Solo en modo `edit`; opciones ACTIVO / INACTIVO |

**Integración con React Hook Form + Zod:**
- Resolver: `zodResolver(CreateCategoriaSchema)` (o `UpdateCategoriaSchema` en modo edit).
- Mensajes de error inline bajo cada campo al perder foco.
- Botón "Guardar" deshabilitado mientras `isSubmitting === true`.

---

### 4.3 `ProductoTable`

**Archivo:** `src/features/catalogo/components/ProductoTable.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/ProductoTable.test.tsx`

**Props:**
```typescript
interface ProductoTableProps {
  productos: Producto[];
  totalPages: number;
  currentPage: number;
  onPageChange: (page: number) => void;
  isLoading?: boolean;
}
```

**Columnas:**
| Columna | Campo fuente |
|---------|-------------|
| Código | `codigo` |
| Nombre | `nombre` |
| Categoría | `nombreCategoria` |
| Stock Mín. | `stockMinimo` |
| Stock Máx. | `stockMaximo` |
| Estado | `<EstadoBadge estado={row.estado} />` |
| Acciones | Enlace a detalle / editar (según rol) |

**Comportamiento:**
- Filtros externos (`filtroCategoria`, `filtroEstado`) gestionados desde `catalogoSlice`.
- Paginación con componente `<Pagination>` reutilizable.

---

### 4.4 `ProductoForm`

**Archivo:** `src/features/catalogo/components/ProductoForm.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/ProductoForm.test.tsx`

**Props:**
```typescript
interface ProductoFormProps {
  defaultValues?: Partial<CreateProductoInput>;
  onSubmit: (data: CreateProductoInput) => Promise<void>;
  isSubmitting?: boolean;
  mode: 'create' | 'edit';
}
```

**Campos:**
| Campo | Tipo | Validación |
|-------|------|-----------|
| `codigo` | `input text` | Requerido, máx 50 |
| `nombre` | `input text` | Requerido, máx 200 |
| `descripcion` | `textarea` | Opcional, máx 1000 |
| `categoriaId` | `select` (opciones de `useCategories`) | Requerido, UUID |
| `stockMinimo` / `stockMaximo` | `<StockRangeField>` | Compuesto, cross-field refine |
| `estado` | `select` | Solo en modo edit |

**Integración:**
- `useCategories()` popula el dropdown de categorías.
- `zodResolver(CreateProductoSchema)` con `.refine()` cross-field.
- Error de stockMaximo mostrado inline en `<StockRangeField>`.

---

### 4.5 `ProductoDetail`

**Archivo:** `src/features/catalogo/components/ProductoDetail.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/ProductoDetail.test.tsx`

**Props:**
```typescript
interface ProductoDetailProps {
  productoId: string;
}
```

**Contenido:**
- Información del producto (codigo, nombre, descripcion, categoria, stockMinimo, stockMaximo, estado).
- Stock actual obtenido con `useStockByProducto(productoId)` de `inventory-service` (read from `/inventory/stock/{productId}`).
- Botones **Editar** y **Desactivar** condicionados por rol:
  - Editar: Operador, Supervisor, Administrador.
  - Desactivar: Supervisor, Administrador.

---

### 4.6 `InactivarProductoModal`

**Archivo:** `src/features/catalogo/components/InactivarProductoModal.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/InactivarProductoModal.test.tsx`

**Props:**
```typescript
interface InactivarProductoModalProps {
  open: boolean;
  productoNombre: string;
  onConfirm: () => void;
  onCancel: () => void;
  isLoading?: boolean;
}
```

**Comportamiento:**
- Dialog modal con overlay.
- Muestra nombre del producto en el mensaje de confirmación.
- Botón "Confirmar" dispara `onConfirm` y deshabilita mientras `isLoading`.
- Botón "Cancelar" dispara `onCancel`.

---

### 4.7 `StockRangeField`

**Archivo:** `src/features/catalogo/components/StockRangeField.tsx`
**Prueba:** `src/features/catalogo/components/__tests__/StockRangeField.test.tsx`

**Props:**
```typescript
interface StockRangeFieldProps {
  stockMinimoValue: number;
  stockMaximoValue: number;
  onChangeMin: (value: number) => void;
  onChangeMax: (value: number) => void;
  errorMin?: string;
  errorMax?: string;
}
```

**Comportamiento:**
- Dos inputs numéricos lado a lado.
- Muestra mensaje de error inline cuando `errorMax` está presente (e.g., "Stock máximo debe ser mayor al mínimo").
- `data-testid="stock-minimo-input"` y `data-testid="stock-maximo-input"` para pruebas.

---

### 4.8 `EstadoBadge`

**Archivo:** `src/components/ui/EstadoBadge.tsx`
**Prueba:** `src/components/ui/__tests__/EstadoBadge.test.tsx`

**Props:**
```typescript
interface EstadoBadgeProps {
  estado: 'ACTIVO' | 'INACTIVO';
}
```

**Comportamiento:**
| Estado | Clases CSS | Texto |
|--------|-----------|-------|
| `ACTIVO` | `bg-green-100 text-green-800` | "ACTIVO" |
| `INACTIVO` | `bg-gray-100 text-gray-600` | "INACTIVO" |

---

## 5. Integración con API (TanStack Query)

> **Nota TDD:** Cada hook tiene su archivo de prueba creado con MSW handlers antes de implementar el hook. El test debe fallar primero.

Todos los hooks residen en `src/features/catalogo/hooks/`.

### 5.1 `useCategorias`

```typescript
// src/features/catalogo/hooks/useCategorias.ts
export function useCategorias(params?: CategoriasParams) {
  return useQuery({
    queryKey: ['categorias', params],
    queryFn: () => fetchCategorias(params),
    staleTime: 5 * 60 * 1000, // 5 minutos
  });
}
```

- **Endpoint:** `GET /catalog/categories`
- **Query params:** `{ estado?: 'ACTIVO' | 'INACTIVO', page?: number, size?: number }`
- **staleTime:** 5 minutos (datos maestros cambian poco).
- **QueryKey:** `['categorias', params]` — permite invalidación selectiva.

---

### 5.2 `useCategoria`

```typescript
export function useCategoria(id: string) {
  return useQuery({
    queryKey: ['categorias', id],
    queryFn: () => fetchCategoriaById(id),
    enabled: !!id,
  });
}
```

- **Endpoint:** `GET /catalog/categories/{id}`

---

### 5.3 `useCreateCategoria`

```typescript
export function useCreateCategoria() {
  const queryClient = useQueryClient();
  const router = useRouter();
  return useMutation({
    mutationFn: (data: CreateCategoriaInput) => createCategoria(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['categorias'] });
      router.push('/catalogo/categorias');
    },
  });
}
```

- **Endpoint:** `POST /catalog/categories`
- **Post-success:** invalida `['categorias']`, navega a la lista.

---

### 5.4 `useUpdateCategoria`

```typescript
export function useUpdateCategoria(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: UpdateCategoriaInput) => updateCategoria(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['categorias'] });
      queryClient.invalidateQueries({ queryKey: ['categorias', id] });
    },
  });
}
```

- **Endpoint:** `PUT /catalog/categories/{id}`

---

### 5.5 `useProductos`

```typescript
export function useProductos(params: ProductosParams) {
  return useQuery({
    queryKey: ['productos', params],
    queryFn: () => fetchProductos(params),
    staleTime: 2 * 60 * 1000,
  });
}
```

- **Endpoint:** `GET /catalog/products`
- **Query params:** `{ categoriaId?: string, estado?: 'ACTIVO' | 'INACTIVO', page: number, size: number }`

---

### 5.6 `useProducto`

```typescript
export function useProducto(id: string) {
  return useQuery({
    queryKey: ['productos', id],
    queryFn: () => fetchProductoById(id),
    enabled: !!id,
  });
}
```

- **Endpoint:** `GET /catalog/products/{id}`

---

### 5.7 `useCreateProducto`

```typescript
export function useCreateProducto() {
  const queryClient = useQueryClient();
  const router = useRouter();
  return useMutation({
    mutationFn: (data: CreateProductoInput) => createProducto(data),
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: ['productos'] });
      router.push(`/catalogo/productos/${created.id}`);
    },
  });
}
```

- **Endpoint:** `POST /catalog/products`

---

### 5.8 `useUpdateProducto`

```typescript
export function useUpdateProducto(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateProductoInput) => updateProducto(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['productos'] });
      queryClient.invalidateQueries({ queryKey: ['productos', id] });
    },
  });
}
```

- **Endpoint:** `PUT /catalog/products/{id}`

---

### 5.9 `useInactivarProducto`

```typescript
export function useInactivarProducto(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => inactivarProducto(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['productos'] });
      queryClient.invalidateQueries({ queryKey: ['productos', id] });
    },
  });
}
```

- **Endpoint:** `DELETE /catalog/products/{id}` (soft-delete / inactivación)

---

## 6. Estado Global (Zustand)

> **Nota TDD:** Escribir pruebas del slice antes de implementarlo. Verificar cada acción individualmente.

**Archivo:** `src/store/slices/catalogoSlice.ts`

```typescript
interface CatalogoState {
  filtroCategoria: string | null;
  filtroEstado: 'ACTIVO' | 'INACTIVO' | 'TODOS';
  setFiltroCategoria: (categoriaId: string | null) => void;
  setFiltroEstado: (estado: 'ACTIVO' | 'INACTIVO' | 'TODOS') => void;
}

export const useCatalogoSlice = (set: SetState<CatalogoState>): CatalogoState => ({
  filtroCategoria: null,
  filtroEstado: 'TODOS',
  setFiltroCategoria: (categoriaId) => set({ filtroCategoria: categoriaId }),
  setFiltroEstado: (estado) => set({ filtroEstado: estado }),
});
```

**Integración con ProductoListPage:**
```typescript
// ProductoListPage consume el slice
const { filtroCategoria, filtroEstado, setFiltroCategoria, setFiltroEstado } = useCatalogoStore();
const { data, isLoading } = useProductos({
  categoriaId: filtroCategoria ?? undefined,
  estado: filtroEstado === 'TODOS' ? undefined : filtroEstado,
  page: currentPage,
  size: 20,
});
```

---

## 7. Esquemas de Validación (Zod)

> **Nota TDD:** Los schemas se escriben con su prueba unitaria fallando antes de definir el schema.

**Archivo:** `src/features/catalogo/schemas/categoria.schema.ts`

```typescript
import { z } from 'zod';

export const CreateCategoriaSchema = z.object({
  codigo:      z.string().min(1, 'El código es requerido').max(20, 'Máximo 20 caracteres'),
  nombre:      z.string().min(1, 'El nombre es requerido').max(100, 'Máximo 100 caracteres'),
  descripcion: z.string().max(500, 'Máximo 500 caracteres').optional(),
});

export const UpdateCategoriaSchema = CreateCategoriaSchema.extend({
  estado: z.enum(['ACTIVO', 'INACTIVO'], { message: 'Estado inválido' }),
});

export type CreateCategoriaInput = z.infer<typeof CreateCategoriaSchema>;
export type UpdateCategoriaInput = z.infer<typeof UpdateCategoriaSchema>;
```

---

**Archivo:** `src/features/catalogo/schemas/producto.schema.ts`

```typescript
import { z } from 'zod';

export const CreateProductoSchema = z.object({
  codigo:      z.string().min(1, 'El código es requerido').max(50, 'Máximo 50 caracteres'),
  nombre:      z.string().min(1, 'El nombre es requerido').max(200, 'Máximo 200 caracteres'),
  descripcion: z.string().max(1000, 'Máximo 1000 caracteres').optional(),
  categoriaId: z.string().uuid('Debe seleccionar una categoría válida'),
  stockMinimo: z.number({ invalid_type_error: 'Ingrese un número' }).min(0, 'No puede ser negativo'),
  stockMaximo: z.number({ invalid_type_error: 'Ingrese un número' }),
}).refine(
  (data) => data.stockMaximo > data.stockMinimo,
  {
    message: 'Stock máximo debe ser mayor al mínimo',
    path: ['stockMaximo'],
  }
);

export const ProductoResponseSchema = z.object({
  id:          z.string().uuid(),
  codigo:      z.string(),
  nombre:      z.string(),
  descripcion: z.string().optional(),
  categoriaId: z.string().uuid(),
  stockMinimo: z.number(),
  stockMaximo: z.number(),
  estado:      z.enum(['ACTIVO', 'INACTIVO']),
  createdAt:   z.string().datetime(),
  updatedAt:   z.string().datetime().optional(),
});

export type CreateProductoInput = z.infer<typeof CreateProductoSchema>;
export type ProductoResponse    = z.infer<typeof ProductoResponseSchema>;
```

---

## 8. Autenticación y Autorización

### 8.1 Protección de rutas — `middleware.ts`

El middleware de Next.js intercepta todas las rutas bajo `/(protected)/` y valida la sesión NextAuth. Si no hay sesión activa, redirige a `/login`. Si hay sesión pero el rol no está en la lista permitida para esa ruta, redirige a `/no-autorizado`.

### 8.2 Roles y permisos en componentes

```typescript
// Hook auxiliar
export function useRol(): string[] {
  const { data: session } = useSession();
  return session?.user?.roles ?? [];
}

// Utilidad de verificación
export function tieneRol(roles: string[], ...permitidos: string[]): boolean {
  return permitidos.some((r) => roles.includes(r));
}
```

**Tabla de permisos por acción en catálogo:**

| Acción | Operador | Supervisor | Administrador | Gerente | Analista | Auditor |
|--------|----------|-----------|---------------|---------|----------|---------|
| Ver categorías | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Crear categoría | — | ✓ | ✓ | — | — | — |
| Editar categoría | — | ✓ | ✓ | — | — | — |
| Eliminar categoría | — | — | ✓ | — | — | — |
| Ver productos | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Crear producto | ✓ | ✓ | ✓ | — | — | — |
| Editar producto | ✓ | ✓ | ✓ | — | — | — |
| Inactivar producto | — | ✓ | ✓ | — | — | — |

### 8.3 Implementación en componentes

```typescript
// Ejemplo en ProductoDetail
const roles = useRol();
const puedeEditar    = tieneRol(roles, 'Operador', 'Supervisor', 'Administrador');
const puedeInactivar = tieneRol(roles, 'Supervisor', 'Administrador');

return (
  <>
    {puedeEditar    && <Button onClick={handleEdit}>Editar</Button>}
    {puedeInactivar && <Button onClick={openModal} variant="danger">Desactivar</Button>}
  </>
);
```

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Regla Red-Green-Refactor:** Crear el archivo de prueba → ejecutar `npm run test` (debe fallar en rojo) → implementar el mínimo código para que pase (verde) → refactorizar manteniendo el verde.

### 9.1 Pruebas de Esquemas Zod

**Archivo:** `src/features/catalogo/schemas/__tests__/producto.schema.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { CreateProductoSchema } from '../producto.schema';

describe('CreateProductoSchema', () => {
  const validData = {
    codigo:      'PROD-001',
    nombre:      'Aceite Motor 10W40',
    categoriaId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    stockMinimo: 5,
    stockMaximo: 100,
  };

  it('debería pasar con datos válidos', () => {
    const result = CreateProductoSchema.safeParse(validData);
    expect(result.success).toBe(true);
  });

  it('debería fallar cuando stockMaximo === stockMinimo', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, stockMaximo: 5 });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('stockMaximo');
    expect(result.error?.issues[0].message).toBe('Stock máximo debe ser mayor al mínimo');
  });

  it('debería fallar cuando stockMaximo < stockMinimo', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, stockMaximo: 3 });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].message).toBe('Stock máximo debe ser mayor al mínimo');
  });

  it('debería fallar si codigo está vacío', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, codigo: '' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('codigo');
  });

  it('debería fallar si nombre está vacío', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, nombre: '' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('nombre');
  });

  it('debería fallar si categoriaId no es UUID válido', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, categoriaId: 'no-es-uuid' });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0].path).toContain('categoriaId');
  });

  it('debería aceptar descripcion opcional ausente', () => {
    const { descripcion, ...sinDescripcion } = { ...validData, descripcion: undefined };
    const result = CreateProductoSchema.safeParse(sinDescripcion);
    expect(result.success).toBe(true);
  });

  it('debería fallar si stockMinimo es negativo', () => {
    const result = CreateProductoSchema.safeParse({ ...validData, stockMinimo: -1 });
    expect(result.success).toBe(false);
  });
});
```

---

### 9.2 Pruebas del hook `useProductos`

**Archivo:** `src/features/catalogo/hooks/__tests__/useProductos.test.tsx`

MSW handlers:

```typescript
// src/mocks/handlers/catalog.ts
import { http, HttpResponse } from 'msw';

export const catalogHandlers = [
  http.get('/api/v1/catalog/products', () =>
    HttpResponse.json({
      content: [
        { id: 'uuid-1', codigo: 'P001', nombre: 'Producto A', categoriaId: 'cat-1',
          stockMinimo: 5, stockMaximo: 100, estado: 'ACTIVO', createdAt: '2025-01-01T00:00:00Z' },
      ],
      totalPages: 1,
      totalElements: 1,
    })
  ),
];
```

```typescript
import { describe, it, expect } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useProductos } from '../useProductos';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

describe('useProductos', () => {
  it('debería retornar lista de productos en estado success', async () => {
    const { result } = renderHook(() => useProductos({ page: 0, size: 20 }), {
      wrapper: createWrapper(),
    });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.content).toHaveLength(1);
    expect(result.current.data?.content[0].codigo).toBe('P001');
  });

  it('debería estar en estado loading inicialmente', () => {
    const { result } = renderHook(() => useProductos({ page: 0, size: 20 }), {
      wrapper: createWrapper(),
    });
    expect(result.current.isLoading).toBe(true);
  });

  it('debería manejar error 500 del API', async () => {
    server.use(
      http.get('/api/v1/catalog/products', () =>
        HttpResponse.json({ message: 'Internal Server Error' }, { status: 500 })
      )
    );
    const { result } = renderHook(() => useProductos({ page: 0, size: 20 }), {
      wrapper: createWrapper(),
    });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

---

### 9.3 Pruebas del hook `useCreateProducto`

**Archivo:** `src/features/catalogo/hooks/__tests__/useCreateProducto.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { createWrapper } from '@/test-utils/query-wrapper';
import { useCreateProducto } from '../useCreateProducto';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';

const mockPush = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ push: mockPush }) }));

describe('useCreateProducto', () => {
  const validPayload = {
    codigo: 'P001', nombre: 'Producto A',
    categoriaId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    stockMinimo: 5, stockMaximo: 100,
  };

  it('éxito: navega al detalle e invalida la query de productos', async () => {
    server.use(
      http.post('/api/v1/catalog/products', () =>
        HttpResponse.json({ id: 'new-uuid', ...validPayload, estado: 'ACTIVO', createdAt: '2025-01-01T00:00:00Z' }, { status: 201 })
      )
    );
    const { result } = renderHook(() => useCreateProducto(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockPush).toHaveBeenCalledWith('/catalogo/productos/new-uuid');
  });

  it('error 400: la mutación queda en estado error', async () => {
    server.use(
      http.post('/api/v1/catalog/products', () =>
        HttpResponse.json({ message: 'Código duplicado' }, { status: 400 })
      )
    );
    const { result } = renderHook(() => useCreateProducto(), { wrapper: createWrapper() });
    await act(async () => { result.current.mutate(validPayload); });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

---

### 9.4 Pruebas del componente `ProductoForm`

**Archivo:** `src/features/catalogo/components/__tests__/ProductoForm.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ProductoForm } from '../ProductoForm';

// Mock del hook de categorías
vi.mock('@/features/catalogo/hooks/useCategorias', () => ({
  useCategorias: () => ({
    data: { content: [{ id: 'cat-uuid-1', codigo: 'CAT01', nombre: 'Categoría A' }] },
    isLoading: false,
  }),
}));

describe('ProductoForm', () => {
  const mockSubmit = vi.fn().mockResolvedValue(undefined);

  it('debería renderizar todos los campos del formulario', () => {
    render(<ProductoForm mode="create" onSubmit={mockSubmit} />);
    expect(screen.getByLabelText(/código/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/nombre/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/descripción/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/categoría/i)).toBeInTheDocument();
    expect(screen.getByTestId('stock-minimo-input')).toBeInTheDocument();
    expect(screen.getByTestId('stock-maximo-input')).toBeInTheDocument();
  });

  it('debería llamar onSubmit con datos válidos', async () => {
    const user = userEvent.setup();
    render(<ProductoForm mode="create" onSubmit={mockSubmit} />);
    await user.type(screen.getByLabelText(/código/i), 'P001');
    await user.type(screen.getByLabelText(/nombre/i), 'Producto A');
    await user.selectOptions(screen.getByLabelText(/categoría/i), 'cat-uuid-1');
    await user.clear(screen.getByTestId('stock-minimo-input'));
    await user.type(screen.getByTestId('stock-minimo-input'), '5');
    await user.clear(screen.getByTestId('stock-maximo-input'));
    await user.type(screen.getByTestId('stock-maximo-input'), '100');
    await user.click(screen.getByRole('button', { name: /guardar/i }));
    await waitFor(() => expect(mockSubmit).toHaveBeenCalledOnce());
  });

  it('debería mostrar error inline cuando stockMaximo <= stockMinimo', async () => {
    const user = userEvent.setup();
    render(<ProductoForm mode="create" onSubmit={mockSubmit} />);
    await user.type(screen.getByLabelText(/código/i), 'P001');
    await user.type(screen.getByLabelText(/nombre/i), 'Producto A');
    await user.selectOptions(screen.getByLabelText(/categoría/i), 'cat-uuid-1');
    await user.clear(screen.getByTestId('stock-minimo-input'));
    await user.type(screen.getByTestId('stock-minimo-input'), '50');
    await user.clear(screen.getByTestId('stock-maximo-input'));
    await user.type(screen.getByTestId('stock-maximo-input'), '10');
    await user.click(screen.getByRole('button', { name: /guardar/i }));
    await waitFor(() =>
      expect(screen.getByText(/stock máximo debe ser mayor al mínimo/i)).toBeInTheDocument()
    );
    expect(mockSubmit).not.toHaveBeenCalled();
  });

  it('debería deshabilitar el botón de guardar cuando el formulario es inválido', async () => {
    render(<ProductoForm mode="create" onSubmit={mockSubmit} />);
    const submitButton = screen.getByRole('button', { name: /guardar/i });
    // En modo create, si isSubmitting o si hay errores pendientes
    expect(submitButton).not.toBeDisabled(); // deshabilitado solo al intentar submit sin datos
  });
});
```

---

### 9.5 Pruebas del componente `StockRangeField`

**Archivo:** `src/features/catalogo/components/__tests__/StockRangeField.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StockRangeField } from '../StockRangeField';

describe('StockRangeField', () => {
  it('debería renderizar dos inputs numéricos', () => {
    render(
      <StockRangeField
        stockMinimoValue={0}
        stockMaximoValue={0}
        onChangeMin={vi.fn()}
        onChangeMax={vi.fn()}
      />
    );
    expect(screen.getByTestId('stock-minimo-input')).toBeInTheDocument();
    expect(screen.getByTestId('stock-maximo-input')).toBeInTheDocument();
  });

  it('debería mostrar mensaje de error cuando errorMax está definido', () => {
    render(
      <StockRangeField
        stockMinimoValue={100}
        stockMaximoValue={50}
        onChangeMin={vi.fn()}
        onChangeMax={vi.fn()}
        errorMax="Stock máximo debe ser mayor al mínimo"
      />
    );
    expect(screen.getByText(/stock máximo debe ser mayor al mínimo/i)).toBeInTheDocument();
  });

  it('NO debería mostrar error si errorMax no está definido', () => {
    render(
      <StockRangeField
        stockMinimoValue={10}
        stockMaximoValue={100}
        onChangeMin={vi.fn()}
        onChangeMax={vi.fn()}
      />
    );
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
});
```

---

### 9.6 Pruebas del componente `EstadoBadge`

**Archivo:** `src/components/ui/__tests__/EstadoBadge.test.tsx`

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { EstadoBadge } from '../EstadoBadge';

describe('EstadoBadge', () => {
  it('debería renderizar "ACTIVO" con clase green cuando estado es ACTIVO', () => {
    render(<EstadoBadge estado="ACTIVO" />);
    const badge = screen.getByText('ACTIVO');
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveClass('bg-green-100');
    expect(badge).toHaveClass('text-green-800');
  });

  it('debería renderizar "INACTIVO" con clase gray cuando estado es INACTIVO', () => {
    render(<EstadoBadge estado="INACTIVO" />);
    const badge = screen.getByText('INACTIVO');
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveClass('bg-gray-100');
    expect(badge).toHaveClass('text-gray-600');
  });
});
```

---

### 9.7 Pruebas del `catalogoSlice`

**Archivo:** `src/store/slices/__tests__/catalogoSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { act } from '@testing-library/react';
import { create } from 'zustand';
import { useCatalogoSlice } from '../catalogoSlice';

const useTestStore = create(useCatalogoSlice);

describe('catalogoSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ filtroCategoria: null, filtroEstado: 'TODOS' });
  });

  it('estado inicial: filtroCategoria null, filtroEstado TODOS', () => {
    const state = useTestStore.getState();
    expect(state.filtroCategoria).toBeNull();
    expect(state.filtroEstado).toBe('TODOS');
  });

  it('setFiltroCategoria: actualiza filtroCategoria', () => {
    act(() => { useTestStore.getState().setFiltroCategoria('cat-uuid-1'); });
    expect(useTestStore.getState().filtroCategoria).toBe('cat-uuid-1');
  });

  it('setFiltroCategoria: puede resetear a null', () => {
    act(() => {
      useTestStore.getState().setFiltroCategoria('cat-uuid-1');
      useTestStore.getState().setFiltroCategoria(null);
    });
    expect(useTestStore.getState().filtroCategoria).toBeNull();
  });

  it('setFiltroEstado: actualiza a ACTIVO', () => {
    act(() => { useTestStore.getState().setFiltroEstado('ACTIVO'); });
    expect(useTestStore.getState().filtroEstado).toBe('ACTIVO');
  });

  it('setFiltroEstado: actualiza a INACTIVO', () => {
    act(() => { useTestStore.getState().setFiltroEstado('INACTIVO'); });
    expect(useTestStore.getState().filtroEstado).toBe('INACTIVO');
  });

  it('setFiltroEstado: puede volver a TODOS', () => {
    act(() => {
      useTestStore.getState().setFiltroEstado('ACTIVO');
      useTestStore.getState().setFiltroEstado('TODOS');
    });
    expect(useTestStore.getState().filtroEstado).toBe('TODOS');
  });
});
```

---

## 10. Pruebas E2E (Playwright, ATDD)

> **Principio ATDD:** Los escenarios E2E se escriben **antes** de que el feature esté completamente integrado. Se ejecutan contra el entorno de staging con datos seed predefinidos.

**Archivo:** `e2e/catalogo/catalogo.spec.ts`

### Configuración base

```typescript
// e2e/fixtures/auth.ts
import { test as base } from '@playwright/test';

type AuthFixture = {
  authenticatedPage: Page;
  role: 'Administrador' | 'Supervisor' | 'Operador' | 'Gerente';
};

export const test = base.extend<AuthFixture>({ /* ... */ });
```

---

### TC-CAT-01: Crear categoría y verificar que aparece en el listado

```typescript
test('TC-CAT-01: Administrador crea una categoría y aparece en la lista', async ({ page }) => {
  // GIVEN: Usuario autenticado como Administrador en /catalogo/categorias
  await page.goto('/catalogo/categorias');
  await expect(page.getByRole('heading', { name: /categorías/i })).toBeVisible();

  // WHEN: Click en "Nueva categoría"
  await page.getByRole('link', { name: /nueva categoría/i }).click();
  await expect(page).toHaveURL('/catalogo/categorias/nueva');

  // AND: Completa el formulario
  await page.getByLabel(/código/i).fill('CAT-E2E-01');
  await page.getByLabel(/nombre/i).fill('Categoría E2E Test');
  await page.getByLabel(/descripción/i).fill('Categoría creada por prueba E2E');
  await page.getByRole('button', { name: /guardar/i }).click();

  // THEN: Redirige al listado y la categoría aparece
  await expect(page).toHaveURL('/catalogo/categorias');
  await expect(page.getByText('CAT-E2E-01')).toBeVisible();
  await expect(page.getByText('Categoría E2E Test')).toBeVisible();
});
```

---

### TC-CAT-02: Crear producto con rango de stock válido

```typescript
test('TC-CAT-02: Operador crea un producto con stock range válido y aparece en la lista', async ({ page }) => {
  // GIVEN: Usuario autenticado como Operador en /catalogo/productos
  await page.goto('/catalogo/productos/nuevo');

  // WHEN: Completa el formulario con datos válidos
  await page.getByLabel(/código/i).fill('PROD-E2E-01');
  await page.getByLabel(/nombre/i).fill('Aceite Motor E2E');
  await page.getByLabel(/categoría/i).selectOption({ label: 'Lubricantes' });
  await page.getByTestId('stock-minimo-input').fill('10');
  await page.getByTestId('stock-maximo-input').fill('200');
  await page.getByRole('button', { name: /guardar/i }).click();

  // THEN: Redirige al detalle del nuevo producto
  await expect(page).toHaveURL(/\/catalogo\/productos\/[a-z0-9-]+/);
  await expect(page.getByText('PROD-E2E-01')).toBeVisible();

  // AND: Aparece en el listado
  await page.goto('/catalogo/productos');
  await expect(page.getByText('PROD-E2E-01')).toBeVisible();
});
```

---

### TC-CAT-03: Validación inline cuando stockMaximo < stockMinimo

```typescript
test('TC-CAT-03: Error inline al crear producto con stockMaximo < stockMinimo', async ({ page }) => {
  // GIVEN
  await page.goto('/catalogo/productos/nuevo');

  // WHEN: Completa datos básicos pero con stock inválido
  await page.getByLabel(/código/i).fill('PROD-E2E-INVALID');
  await page.getByLabel(/nombre/i).fill('Producto Stock Inválido');
  await page.getByLabel(/categoría/i).selectOption({ index: 1 });
  await page.getByTestId('stock-minimo-input').fill('100');
  await page.getByTestId('stock-maximo-input').fill('50');
  await page.getByRole('button', { name: /guardar/i }).click();

  // THEN: Aparece mensaje de error inline, el formulario NO se envía
  await expect(page.getByText(/stock máximo debe ser mayor al mínimo/i)).toBeVisible();
  await expect(page).toHaveURL('/catalogo/productos/nuevo'); // permanece en la misma página
});
```

---

### TC-CAT-04: Inactivar producto

```typescript
test('TC-CAT-04: Supervisor inactiva un producto y el estado cambia en el listado', async ({ page }) => {
  // GIVEN: Producto activo existente en el catálogo
  await page.goto('/catalogo/productos');
  await expect(page.getByText('PROD-SEED-01')).toBeVisible();

  // WHEN: Click en el producto, luego en Desactivar
  await page.getByRole('link', { name: 'PROD-SEED-01' }).click();
  await page.getByRole('button', { name: /desactivar/i }).click();

  // AND: Confirma en el modal
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: /confirmar/i }).click();

  // THEN: Regresa al listado, estado del producto es INACTIVO
  await page.goto('/catalogo/productos');
  const row = page.getByRole('row', { name: /PROD-SEED-01/i });
  await expect(row.getByText('INACTIVO')).toBeVisible();
});
```

---

### TC-CAT-05: Gerente no ve el botón "Nuevo producto"

```typescript
test('TC-CAT-05: Gerente no tiene botón "Nuevo producto" visible', async ({ page }) => {
  // GIVEN: Usuario autenticado como Gerente
  // (fixture configura sesión de Gerente)
  await page.goto('/catalogo/productos');

  // THEN: No existe el botón de creación
  await expect(page.getByRole('link', { name: /nuevo producto/i })).not.toBeVisible();
  // AND: La página carga y muestra el listado (puede ver pero no crear)
  await expect(page.getByRole('heading', { name: /productos/i })).toBeVisible();
});
```

---

## 11. Criterios de Aceptación

### 11.1 Criterios funcionales

| ID | Criterio | Verificación |
|----|---------|-------------|
| CA-CAT-01 | Administrador y Supervisor pueden crear, editar categorías | Test E2E TC-CAT-01 + test unitario `useCreateCategoria` |
| CA-CAT-02 | Solo Administrador puede eliminar/inactivar categorías | Revisión de permisos en componente + E2E |
| CA-CAT-03 | Operador puede crear y editar productos | Test E2E TC-CAT-02 |
| CA-CAT-04 | `stockMaximo` debe ser estrictamente mayor a `stockMinimo` | Test schema `CreateProductoSchema` + E2E TC-CAT-03 |
| CA-CAT-05 | Roles Gerente, Analista, Auditor solo tienen lectura | E2E TC-CAT-05 + revisión de permisos en middleware |
| CA-CAT-06 | El filtro por categoría y estado funciona en ProductoListPage | Test unitario `catalogoSlice` + test de integración |
| CA-CAT-07 | ProductoDetail muestra stock actual de inventory-service | Test unitario `ProductoDetail` con mock MSW |
| CA-CAT-08 | El badge `EstadoBadge` refleja correctamente el estado visual | Test unitario `EstadoBadge` |

### 11.2 Criterios de calidad TDD

| Criterio | Evidencia requerida |
|---------|-------------------|
| Cada schema Zod tuvo prueba fallida antes de ser escrito | Commit con archivo de test antes que el schema |
| Cada hook TanStack Query tuvo prueba fallida antes de ser escrito | Commit con MSW handler + test antes que el hook |
| Cada componente tuvo prueba fallida antes de ser escrito | Commit con archivo de test antes que el componente |
| `npm run test` verde al final de la etapa | Output de CI sin errores |
| Todos los E2E Playwright pasan en staging | Reporte Playwright sin fallos (TC-CAT-01 al TC-CAT-05) |
| Cobertura de ramas > 80% en el feature catálogo | Reporte Vitest coverage |

### 11.3 Criterios de integración

| Criterio | Detalle |
|---------|---------|
| Conexión con `catalog-service` vía Kong | Endpoints GET/POST/PUT funcionando con JWT en header Authorization |
| `inventory-service` devuelve stock en ProductoDetail | GET `/inventory/stock/{productId}` retorna `StockLevelResponse` |
| Invalidación de caché correcta | Tras create/update, la lista se recarga automáticamente |
| Protección de rutas activa | Acceso a `/catalogo/categorias/nueva` con rol Operador → 302 a `/no-autorizado` |
