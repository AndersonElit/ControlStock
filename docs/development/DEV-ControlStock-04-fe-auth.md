# Etapa 4a — Frontend: Feature Auth

## 1. Resumen del Feature

| Campo | Valor |
|---|---|
| Feature ID | FE-AUTH |
| Documento | DEV-ControlStock-04-fe-auth.md |
| Etapa SDLC | 4 — Implementación Frontend |
| Sprint sugerido | Sprint 1 |
| Prioridad | Crítica (bloqueante para todos los demás features) |
| Dependencias | Keycloak realm `controlstock` configurado y operativo |

El feature **Auth** implementa el flujo completo de autenticación usando **NextAuth.js 4** con Keycloak como proveedor OIDC. Cubre la página de login, el callback OAuth2, la gestión de sesión con JWT stateless, el middleware de protección de rutas y el logout con limpieza de sesión en Keycloak.

---

## 2. Contexto y Alcance

### 2.1 Descripción funcional

Al acceder a la aplicación ControlStock, los usuarios no autenticados son redirigidos automáticamente a `/login`. Desde allí pueden iniciar sesión haciendo clic en el botón "Iniciar sesión con Keycloak", que dispara el flujo OAuth2/OIDC: redirección a Keycloak, autenticación de credenciales, redirect de vuelta al callback `/auth/callback`, y finalmente creación de la sesión local con NextAuth.js.

Una vez autenticado, el usuario es redirigido al `/dashboard`. Las rutas protegidas verifican la existencia y validez del token JWT en cada navegación gracias al middleware de Next.js.

### 2.2 Rutas del feature

| Ruta | Tipo | Acceso | Descripción |
|---|---|---|---|
| `/login` | Pública | Sin autenticación | Página de login con botón de inicio de sesión |
| `/auth/callback` | Pública | Sin autenticación | Callback OAuth2 gestionado por NextAuth.js |
| `/logout` | Pública | Sin autenticación | Limpieza de sesión local + logout de Keycloak |

### 2.3 Rutas protegidas (middleware)

Todas las rutas que **no** coincidan con `/login`, `/auth/*` o recursos estáticos son protegidas. El middleware verifica la sesión y redirige a `/login` si no existe o ha expirado.

### 2.4 Roles involucrados

Todos los roles pueden acceder a la página de login. No hay restricción de rol en este feature; las restricciones por rol se aplican en features posteriores.

| Rol | Acceso |
|---|---|
| Administrador | Login / Logout |
| Supervisor | Login / Logout |
| Operador | Login / Logout |
| Gerente | Login / Logout |
| Analista | Login / Logout |
| Auditor | Login / Logout |
| APIConsumer | Login / Logout |

---

## 3. Backend Consumido

Este feature **no consume servicios de backend propios**. La autenticación es gestionada completamente por NextAuth.js como intermediario con Keycloak.

| Servicio | Descripción |
|---|---|
| Keycloak | Proveedor OIDC. Realm: `controlstock`. Endpoints gestionados por NextAuth.js |
| Kong API Gateway | No involucrado en auth, pero valida el JWT RS256 en llamadas posteriores a la API |

### 3.1 Variables de entorno requeridas

```env
KEYCLOAK_URL=http://<VPS_IP>:8080
KEYCLOAK_REALM=controlstock
KEYCLOAK_CLIENT_ID=controlstock-web
KEYCLOAK_CLIENT_SECRET=<secret>
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=<random-32-bytes>
```

---

## 4. Arquitectura del Feature

```
src/
├── app/
│   ├── (public)/
│   │   ├── login/
│   │   │   └── page.tsx            # LoginPage — Server Component
│   │   └── logout/
│   │       └── page.tsx            # LogoutPage — Client Component
│   └── api/
│       └── auth/
│           └── [...nextauth]/
│               └── route.ts        # NextAuth.js API route handler
├── components/
│   └── auth/
│       ├── LoginButton.tsx         # Client Component — botón de inicio de sesión
│       ├── LoginButton.test.tsx
│       ├── AuthGuard.tsx           # HOC de protección de rutas
│       └── AuthGuard.test.tsx
├── providers/
│   └── SessionProvider.tsx         # NextAuth.js SessionProvider wrapper
├── store/
│   └── slices/
│       ├── authSlice.ts            # Zustand slice de autenticación
│       └── authSlice.test.ts
├── schemas/
│   └── auth/
│       ├── sessionSchema.ts        # Zod: shape del session object
│       ├── keycloakTokenSchema.ts  # Zod: JWT claims de Keycloak
│       └── auth.schemas.test.ts
├── lib/
│   └── auth/
│       └── nextauth.config.ts      # Configuración de NextAuth.js
└── middleware.ts                   # Next.js middleware de protección
```

---

## 5. Configuración de NextAuth.js

### 5.1 `src/lib/auth/nextauth.config.ts`

```typescript
import type { NextAuthOptions } from 'next-auth'
import KeycloakProvider from 'next-auth/providers/keycloak'

export const authOptions: NextAuthOptions = {
  providers: [
    KeycloakProvider({
      clientId: process.env.KEYCLOAK_CLIENT_ID!,
      clientSecret: process.env.KEYCLOAK_CLIENT_SECRET!,
      issuer: `${process.env.KEYCLOAK_URL}/realms/${process.env.KEYCLOAK_REALM}`,
    }),
  ],
  session: {
    strategy: 'jwt',
  },
  callbacks: {
    async jwt({ token, account, profile }) {
      // Primer login: enriquecer token con datos de Keycloak
      if (account && profile) {
        token.accessToken = account.access_token
        token.refreshToken = account.refresh_token
        token.expiresAt = account.expires_at
        // Extraer roles del realm de Keycloak
        const keycloakProfile = profile as Record<string, unknown>
        const realmAccess = keycloakProfile?.realm_access as { roles?: string[] }
        token.roles = realmAccess?.roles ?? []
        token.sub = profile.sub
        token.email = profile.email
        token.name = profile.name
      }

      // Verificar expiración del token
      const now = Math.floor(Date.now() / 1000)
      if (token.expiresAt && typeof token.expiresAt === 'number' && now < token.expiresAt) {
        return token
      }

      // Token expirado: intentar refresh
      return await refreshAccessToken(token)
    },
    async session({ session, token }) {
      session.user = {
        id: token.sub as string,
        email: token.email as string,
        name: token.name as string,
        roles: (token.roles as string[]) ?? [],
      }
      session.accessToken = token.accessToken as string
      session.error = token.error as string | undefined
      return session
    },
  },
  pages: {
    signIn: '/login',
    error: '/login',
  },
}

async function refreshAccessToken(token: Record<string, unknown>) {
  try {
    const url = `${process.env.KEYCLOAK_URL}/realms/${process.env.KEYCLOAK_REALM}/protocol/openid-connect/token`
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: process.env.KEYCLOAK_CLIENT_ID!,
        client_secret: process.env.KEYCLOAK_CLIENT_SECRET!,
        grant_type: 'refresh_token',
        refresh_token: token.refreshToken as string,
      }),
    })

    const refreshed = await response.json()

    if (!response.ok) throw refreshed

    return {
      ...token,
      accessToken: refreshed.access_token,
      refreshToken: refreshed.refresh_token ?? token.refreshToken,
      expiresAt: Math.floor(Date.now() / 1000) + refreshed.expires_in,
      error: undefined,
    }
  } catch {
    return { ...token, error: 'RefreshAccessTokenError' }
  }
}
```

### 5.2 `src/app/api/auth/[...nextauth]/route.ts`

```typescript
import NextAuth from 'next-auth'
import { authOptions } from '@/lib/auth/nextauth.config'

const handler = NextAuth(authOptions)

export { handler as GET, handler as POST }
```

---

## 6. Middleware de Protección de Rutas

### 6.1 `src/middleware.ts`

```typescript
import { withAuth } from 'next-auth/middleware'
import { NextResponse } from 'next/server'

export default withAuth(
  function middleware(req) {
    const token = req.nextauth.token

    // Si el token tiene error de refresh, redirigir a login
    if (token?.error === 'RefreshAccessTokenError') {
      return NextResponse.redirect(new URL('/login', req.url))
    }

    return NextResponse.next()
  },
  {
    callbacks: {
      authorized: ({ token }) => !!token,
    },
    pages: {
      signIn: '/login',
    },
  }
)

export const config = {
  matcher: [
    // Proteger todo excepto rutas públicas y recursos estáticos
    '/((?!login|auth|logout|api/auth|_next/static|_next/image|favicon.ico|public).*)',
  ],
}
```

---

## 7. Zod Schemas

### 7.1 `src/schemas/auth/sessionSchema.ts`

```typescript
import { z } from 'zod'

export const SessionUserSchema = z.object({
  id: z.string().uuid('El ID de usuario debe ser un UUID válido'),
  email: z.string().email('El email debe tener formato válido'),
  name: z.string().min(1, 'El nombre no puede estar vacío'),
  roles: z.array(z.string()).min(1, 'El usuario debe tener al menos un rol'),
})

export const SessionSchema = z.object({
  user: SessionUserSchema,
  expires: z.string().datetime('La fecha de expiración debe ser un datetime ISO válido'),
  accessToken: z.string().optional(),
  error: z.string().optional(),
})

export type SessionUser = z.infer<typeof SessionUserSchema>
export type Session = z.infer<typeof SessionSchema>
```

### 7.2 `src/schemas/auth/keycloakTokenSchema.ts`

```typescript
import { z } from 'zod'

export const RealmAccessSchema = z.object({
  roles: z.array(z.string()).min(1, 'El token debe contener al menos un rol de realm'),
})

export const KeycloakTokenSchema = z.object({
  sub: z.string().min(1, 'El campo sub es obligatorio'),
  email: z.string().email('El email en el token debe ser válido'),
  name: z.string().min(1, 'El nombre en el token es obligatorio'),
  realm_access: RealmAccessSchema,
  exp: z.number().int().positive('El campo exp debe ser un timestamp positivo'),
  iat: z.number().int().positive('El campo iat debe ser un timestamp positivo'),
})

export type KeycloakToken = z.infer<typeof KeycloakTokenSchema>
```

---

## 8. Zustand Slice

### 8.1 `src/store/slices/authSlice.ts`

```typescript
import { StateCreator } from 'zustand'

export interface AuthUser {
  id: string
  email: string
  name: string
  roles: string[]
}

export interface AuthState {
  user: AuthUser | null
  isAuthenticated: boolean
  setUser: (user: AuthUser) => void
  clearUser: () => void
  hasRole: (role: string) => boolean
}

export const createAuthSlice: StateCreator<AuthState> = (set, get) => ({
  user: null,
  isAuthenticated: false,

  setUser: (user: AuthUser) =>
    set({
      user,
      isAuthenticated: true,
    }),

  clearUser: () =>
    set({
      user: null,
      isAuthenticated: false,
    }),

  hasRole: (role: string) => {
    const { user } = get()
    return user?.roles.includes(role) ?? false
  },
})
```

---

## 9. Componentes

### 9.1 `src/app/(public)/login/page.tsx` — LoginPage (Server Component)

```typescript
import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth/nextauth.config'
import { LoginButton } from '@/components/auth/LoginButton'

export default async function LoginPage() {
  const session = await getServerSession(authOptions)

  // Si ya está autenticado, redirigir al dashboard
  if (session) {
    redirect('/dashboard')
  }

  return (
    <main className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="bg-white rounded-2xl shadow-lg p-10 w-full max-w-md text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">ControlStock</h1>
        <p className="text-gray-500 mb-8">Sistema de gestión de inventario Retail</p>
        <LoginButton />
      </div>
    </main>
  )
}
```

### 9.2 `src/components/auth/LoginButton.tsx` — Client Component

```typescript
'use client'

import { signIn } from 'next-auth/react'
import { useState } from 'react'

export function LoginButton() {
  const [isLoading, setIsLoading] = useState(false)

  const handleSignIn = async () => {
    setIsLoading(true)
    try {
      await signIn('keycloak', { callbackUrl: '/dashboard' })
    } catch {
      setIsLoading(false)
    }
  }

  return (
    <button
      onClick={handleSignIn}
      disabled={isLoading}
      data-testid="login-button"
      className="w-full bg-blue-600 hover:bg-blue-700 disabled:opacity-60 text-white font-semibold py-3 px-6 rounded-lg transition-colors"
    >
      {isLoading ? 'Redirigiendo...' : 'Iniciar sesión con Keycloak'}
    </button>
  )
}
```

### 9.3 `src/providers/SessionProvider.tsx`

```typescript
'use client'

import { SessionProvider as NextAuthSessionProvider } from 'next-auth/react'

interface Props {
  children: React.ReactNode
}

export function SessionProvider({ children }: Props) {
  return <NextAuthSessionProvider>{children}</NextAuthSessionProvider>
}
```

### 9.4 `src/components/auth/AuthGuard.tsx` — HOC de protección

```typescript
'use client'

import { useSession } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import { useEffect } from 'react'

interface AuthGuardProps {
  children: React.ReactNode
  fallback?: React.ReactNode
}

export function AuthGuard({ children, fallback = null }: AuthGuardProps) {
  const { data: session, status } = useSession()
  const router = useRouter()

  useEffect(() => {
    if (status === 'unauthenticated') {
      router.push('/login')
    }
  }, [status, router])

  if (status === 'loading') {
    return <>{fallback}</>
  }

  if (!session) {
    return null
  }

  return <>{children}</>
}
```

### 9.5 `src/app/(public)/logout/page.tsx`

```typescript
'use client'

import { signOut } from 'next-auth/react'
import { useEffect } from 'react'

export default function LogoutPage() {
  useEffect(() => {
    signOut({
      callbackUrl: '/login',
      redirect: true,
    })
  }, [])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <p className="text-gray-500">Cerrando sesión...</p>
    </div>
  )
}
```

---

## 10. TDD — Pruebas Unitarias (Vitest + RTL)

> **Regla TDD:** Escribir el test ANTES del código (Red → Green → Refactor).

### 10.1 `src/schemas/auth/auth.schemas.test.ts`

```typescript
import { describe, it, expect } from 'vitest'
import { SessionSchema } from './sessionSchema'
import { KeycloakTokenSchema } from './keycloakTokenSchema'

// ─── SessionSchema ────────────────────────────────────────────────────────────

describe('SessionSchema', () => {
  const validSession = {
    user: {
      id: '550e8400-e29b-41d4-a716-446655440000',
      email: 'usuario@controlstock.com',
      name: 'Juan Pérez',
      roles: ['Operador'],
    },
    expires: '2025-12-31T23:59:59.000Z',
  }

  it('acepta una sesión válida', () => {
    expect(() => SessionSchema.parse(validSession)).not.toThrow()
  })

  it('rechaza cuando roles es un array vacío', () => {
    const result = SessionSchema.safeParse({
      ...validSession,
      user: { ...validSession.user, roles: [] },
    })
    expect(result.success).toBe(false)
  })

  it('rechaza cuando expires no es un datetime ISO', () => {
    const result = SessionSchema.safeParse({
      ...validSession,
      expires: 'no-es-una-fecha',
    })
    expect(result.success).toBe(false)
  })

  it('rechaza cuando falta el campo user', () => {
    const { user: _user, ...withoutUser } = validSession
    const result = SessionSchema.safeParse(withoutUser)
    expect(result.success).toBe(false)
  })

  it('rechaza email con formato inválido', () => {
    const result = SessionSchema.safeParse({
      ...validSession,
      user: { ...validSession.user, email: 'no-es-email' },
    })
    expect(result.success).toBe(false)
  })
})

// ─── KeycloakTokenSchema ──────────────────────────────────────────────────────

describe('KeycloakTokenSchema', () => {
  const validToken = {
    sub: 'user-uuid-keycloak',
    email: 'usuario@controlstock.com',
    name: 'Juan Pérez',
    realm_access: { roles: ['Operador', 'offline_access'] },
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
  }

  it('acepta un token válido', () => {
    expect(() => KeycloakTokenSchema.parse(validToken)).not.toThrow()
  })

  it('rechaza cuando falta sub', () => {
    const { sub: _sub, ...withoutSub } = validToken
    const result = KeycloakTokenSchema.safeParse(withoutSub)
    expect(result.success).toBe(false)
  })

  it('rechaza cuando realm_access.roles está vacío', () => {
    const result = KeycloakTokenSchema.safeParse({
      ...validToken,
      realm_access: { roles: [] },
    })
    expect(result.success).toBe(false)
  })

  it('rechaza cuando realm_access está ausente', () => {
    const { realm_access: _ra, ...withoutRA } = validToken
    const result = KeycloakTokenSchema.safeParse(withoutRA)
    expect(result.success).toBe(false)
  })

  it('rechaza email inválido en token', () => {
    const result = KeycloakTokenSchema.safeParse({
      ...validToken,
      email: 'malformado',
    })
    expect(result.success).toBe(false)
  })
})
```

### 10.2 `src/components/auth/LoginButton.test.tsx`

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { LoginButton } from './LoginButton'

// Mock de next-auth/react
vi.mock('next-auth/react', () => ({
  signIn: vi.fn(),
}))

import { signIn } from 'next-auth/react'

describe('LoginButton', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renderiza el botón con el texto correcto', () => {
    render(<LoginButton />)
    expect(screen.getByTestId('login-button')).toHaveTextContent(
      'Iniciar sesión con Keycloak'
    )
  })

  it('el botón está habilitado en estado idle', () => {
    render(<LoginButton />)
    expect(screen.getByTestId('login-button')).not.toBeDisabled()
  })

  it('llama a signIn con keycloak al hacer clic', async () => {
    const mockSignIn = vi.mocked(signIn)
    mockSignIn.mockResolvedValue(undefined as never)

    render(<LoginButton />)
    fireEvent.click(screen.getByTestId('login-button'))

    await waitFor(() => {
      expect(mockSignIn).toHaveBeenCalledWith('keycloak', { callbackUrl: '/dashboard' })
    })
  })

  it('muestra estado de carga después del clic', async () => {
    const mockSignIn = vi.mocked(signIn)
    // Promesa que nunca resuelve para mantener el estado loading
    mockSignIn.mockImplementation(() => new Promise(() => {}))

    render(<LoginButton />)
    fireEvent.click(screen.getByTestId('login-button'))

    await waitFor(() => {
      expect(screen.getByTestId('login-button')).toHaveTextContent('Redirigiendo...')
      expect(screen.getByTestId('login-button')).toBeDisabled()
    })
  })
})
```

### 10.3 `src/store/slices/authSlice.test.ts`

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { create } from 'zustand'
import { createAuthSlice, AuthState } from './authSlice'

const useTestStore = create<AuthState>()(createAuthSlice)

describe('authSlice', () => {
  beforeEach(() => {
    useTestStore.setState({ user: null, isAuthenticated: false })
  })

  it('estado inicial es usuario null y no autenticado', () => {
    const state = useTestStore.getState()
    expect(state.user).toBeNull()
    expect(state.isAuthenticated).toBe(false)
  })

  it('setUser establece el usuario y activa isAuthenticated', () => {
    const user = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      email: 'admin@controlstock.com',
      name: 'Admin',
      roles: ['Administrador'],
    }
    useTestStore.getState().setUser(user)
    const state = useTestStore.getState()
    expect(state.user).toEqual(user)
    expect(state.isAuthenticated).toBe(true)
  })

  it('clearUser elimina el usuario y desactiva isAuthenticated', () => {
    useTestStore.getState().setUser({
      id: 'uuid',
      email: 'a@b.com',
      name: 'A',
      roles: ['Operador'],
    })
    useTestStore.getState().clearUser()
    const state = useTestStore.getState()
    expect(state.user).toBeNull()
    expect(state.isAuthenticated).toBe(false)
  })

  it('hasRole retorna true cuando el usuario tiene el rol', () => {
    useTestStore.getState().setUser({
      id: 'uuid',
      email: 'sup@b.com',
      name: 'Sup',
      roles: ['Supervisor', 'Operador'],
    })
    expect(useTestStore.getState().hasRole('Supervisor')).toBe(true)
  })

  it('hasRole retorna false cuando el usuario no tiene el rol', () => {
    useTestStore.getState().setUser({
      id: 'uuid',
      email: 'op@b.com',
      name: 'Op',
      roles: ['Operador'],
    })
    expect(useTestStore.getState().hasRole('Administrador')).toBe(false)
  })

  it('hasRole retorna false cuando no hay usuario', () => {
    expect(useTestStore.getState().hasRole('Operador')).toBe(false)
  })
})
```

### 10.4 `src/components/auth/AuthGuard.test.tsx`

```typescript
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AuthGuard } from './AuthGuard'

const mockPush = vi.fn()

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: mockPush }),
}))

vi.mock('next-auth/react', () => ({
  useSession: vi.fn(),
}))

import { useSession } from 'next-auth/react'

describe('AuthGuard', () => {
  it('redirige a /login cuando el status es unauthenticated', () => {
    vi.mocked(useSession).mockReturnValue({
      data: null,
      status: 'unauthenticated',
      update: vi.fn(),
    })

    render(
      <AuthGuard>
        <p>Contenido protegido</p>
      </AuthGuard>
    )

    expect(mockPush).toHaveBeenCalledWith('/login')
    expect(screen.queryByText('Contenido protegido')).not.toBeInTheDocument()
  })

  it('renderiza el fallback mientras carga la sesión', () => {
    vi.mocked(useSession).mockReturnValue({
      data: null,
      status: 'loading',
      update: vi.fn(),
    })

    render(
      <AuthGuard fallback={<p>Cargando...</p>}>
        <p>Contenido protegido</p>
      </AuthGuard>
    )

    expect(screen.getByText('Cargando...')).toBeInTheDocument()
    expect(screen.queryByText('Contenido protegido')).not.toBeInTheDocument()
  })

  it('renderiza los children cuando el usuario está autenticado', () => {
    vi.mocked(useSession).mockReturnValue({
      data: {
        user: { id: 'uuid', email: 'a@b.com', name: 'A', roles: ['Operador'] },
        expires: '2025-12-31T23:59:59.000Z',
      } as never,
      status: 'authenticated',
      update: vi.fn(),
    })

    render(
      <AuthGuard>
        <p>Contenido protegido</p>
      </AuthGuard>
    )

    expect(screen.getByText('Contenido protegido')).toBeInTheDocument()
  })
})
```

---

## 11. E2E — Pruebas ATDD con Playwright

> **Regla ATDD:** Describir los escenarios E2E ANTES de la integración. Estas pruebas guían el diseño de componentes e interacciones.

### Archivo: `e2e/auth/auth.spec.ts`

```typescript
import { test, expect } from '@playwright/test'

// ─── TC-AUTH-01: Flujo completo de login ─────────────────────────────────────
test.describe('TC-AUTH-01: Login con Keycloak', () => {
  test('el usuario puede iniciar sesión y es redirigido al dashboard', async ({ page }) => {
    // DADO que el usuario no está autenticado
    await page.goto('/login')

    // ENTONCES ve la página de login con el botón
    await expect(page.getByTestId('login-button')).toBeVisible()
    await expect(page.getByTestId('login-button')).toHaveText('Iniciar sesión con Keycloak')

    // CUANDO hace clic en el botón de login
    await page.getByTestId('login-button').click()

    // ENTONCES es redirigido al formulario de Keycloak
    await expect(page).toHaveURL(/.*keycloak.*\/login/)

    // CUANDO introduce credenciales válidas
    await page.fill('#username', process.env.TEST_USER_EMAIL!)
    await page.fill('#password', process.env.TEST_USER_PASSWORD!)
    await page.click('#kc-login')

    // ENTONCES es redirigido al dashboard
    await expect(page).toHaveURL('/dashboard')

    // Y la sesión está activa (el header muestra el nombre del usuario)
    await expect(page.getByTestId('user-name')).toBeVisible()
  })
})

// ─── TC-AUTH-02: Token expirado redirige a login ──────────────────────────────
test.describe('TC-AUTH-02: Token expirado', () => {
  test('navegar a ruta protegida con token expirado redirige a /login', async ({ page }) => {
    // DADO que hay una sesión con token expirado (simulado via cookie manipulada)
    await page.context().addCookies([
      {
        name: 'next-auth.session-token',
        value: 'token-expirado-invalido',
        domain: 'localhost',
        path: '/',
      },
    ])

    // CUANDO intenta navegar a una ruta protegida
    await page.goto('/dashboard')

    // ENTONCES es redirigido a la página de login
    await expect(page).toHaveURL('/login')

    // Y ve el botón de inicio de sesión
    await expect(page.getByTestId('login-button')).toBeVisible()
  })
})

// ─── TC-AUTH-03: Logout limpia la sesión ─────────────────────────────────────
test.describe('TC-AUTH-03: Logout', () => {
  test.use({ storageState: 'e2e/fixtures/authenticated-user.json' })

  test('el usuario puede cerrar sesión y es redirigido a /login', async ({ page }) => {
    // DADO que el usuario está autenticado y en el dashboard
    await page.goto('/dashboard')
    await expect(page).toHaveURL('/dashboard')

    // CUANDO navega a /logout
    await page.goto('/logout')

    // ENTONCES la sesión se limpia y es redirigido a /login
    await expect(page).toHaveURL('/login')

    // Y no puede acceder a rutas protegidas
    await page.goto('/dashboard')
    await expect(page).toHaveURL('/login')
  })
})
```

### Fixtures y configuración Playwright

```typescript
// e2e/fixtures/setup-auth.ts — generación del estado autenticado para tests
import { chromium } from '@playwright/test'

async function globalSetup() {
  const browser = await chromium.launch()
  const page = await browser.newPage()

  await page.goto('/login')
  await page.getByTestId('login-button').click()
  await page.waitForURL(/keycloak/)
  await page.fill('#username', process.env.TEST_USER_EMAIL!)
  await page.fill('#password', process.env.TEST_USER_PASSWORD!)
  await page.click('#kc-login')
  await page.waitForURL('/dashboard')

  await page.context().storageState({ path: 'e2e/fixtures/authenticated-user.json' })
  await browser.close()
}

export default globalSetup
```

---

## 12. Criterios de Aceptación

| ID | Criterio | Verificación |
|---|---|---|
| AC-AUTH-01 | Usuario no autenticado accede a ruta protegida → redirigido a `/login` | Test E2E TC-AUTH-02 |
| AC-AUTH-02 | Usuario autenticado accede a `/login` → redirigido a `/dashboard` | Test unitario LoginPage |
| AC-AUTH-03 | Clic en "Iniciar sesión" → flujo Keycloak → sesión creada | Test E2E TC-AUTH-01 |
| AC-AUTH-04 | Token expirado → refresh automático; si falla → redirige a `/login` | Test unitario authOptions |
| AC-AUTH-05 | Logout → sesión destruida → `/login` | Test E2E TC-AUTH-03 |
| AC-AUTH-06 | authSlice contiene user con roles tras autenticación | Test unitario authSlice |
| AC-AUTH-07 | SessionSchema válida en la shape de NextAuth.js | Test unitario schemas |

---

## 13. Checklist de Implementación

- [ ] **RED:** Escribir tests de schemas (`SessionSchema`, `KeycloakTokenSchema`) — fallan
- [ ] **GREEN:** Implementar schemas — tests pasan
- [ ] **RED:** Escribir tests de `authSlice` — fallan
- [ ] **GREEN:** Implementar `authSlice` — tests pasan
- [ ] **RED:** Escribir tests de `LoginButton` — fallan
- [ ] **GREEN:** Implementar `LoginButton` — tests pasan
- [ ] **RED:** Escribir tests de `AuthGuard` — fallan
- [ ] **GREEN:** Implementar `AuthGuard` — tests pasan
- [ ] **REFACTOR:** Revisar cobertura y legibilidad
- [ ] Escribir escenarios Playwright (ATDD) antes de integración E2E
- [ ] Configurar variables de entorno en `.env.local`
- [ ] Verificar configuración de Keycloak realm y client
- [ ] PR con al menos 80% de cobertura en este feature
