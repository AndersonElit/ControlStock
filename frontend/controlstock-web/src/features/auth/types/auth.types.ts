export interface AuthUser {
  id: string
  email: string
  name: string
  role: UserRole
  avatar?: string
}

export type UserRole = 'admin' | 'manager' | 'user'

export interface LoginCredentials {
  email: string
  password: string
}

export interface AuthTokens {
  accessToken: string
  refreshToken: string
  expiresIn: number
}

export interface AuthResponse {
  user: AuthUser
  tokens: AuthTokens
}
