import { post } from '@/lib/api/client'

import type { AuthResponse, LoginCredentials } from '../types/auth.types'

export const authService = {
  async login(credentials: LoginCredentials): Promise<AuthResponse> {
    return post<AuthResponse>('/auth/login', credentials)
  },

  async logout(): Promise<void> {
    return post('/auth/logout')
  },

  async refreshToken(refreshToken: string): Promise<Pick<AuthResponse, 'tokens'>> {
    return post('/auth/refresh', { refreshToken })
  },

  async me(): Promise<AuthResponse['user']> {
    return post('/auth/me')
  },
}
