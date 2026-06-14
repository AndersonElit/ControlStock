import type { AxiosInstance, InternalAxiosRequestConfig, AxiosResponse, AxiosError } from 'axios'

import { handleApiError } from './error-handler'

export function setupInterceptors(client: AxiosInstance): void {
  client.interceptors.request.use(
    (config: InternalAxiosRequestConfig) => {
      const token = getAccessToken()
      if (token) {
        config.headers.Authorization = `Bearer ${token}`
      }
      return config
    },
    (error: AxiosError) => Promise.reject(error)
  )

  client.interceptors.response.use(
    (response: AxiosResponse) => response,
    async (error: AxiosError) => {
      const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }

      if (error.response?.status === 401 && !originalRequest._retry) {
        originalRequest._retry = true
        try {
          await refreshAccessToken()
          const newToken = getAccessToken()
          if (newToken) {
            originalRequest.headers.Authorization = `Bearer ${newToken}`
          }
          return client(originalRequest)
        } catch {
          clearTokens()
          window.location.href = '/login'
        }
      }

      return Promise.reject(handleApiError(error))
    }
  )
}

function getAccessToken(): string | null {
  if (typeof window === 'undefined') return null
  return localStorage.getItem('access_token')
}

async function refreshAccessToken(): Promise<void> {
  // Implement refresh token logic
}

function clearTokens(): void {
  if (typeof window === 'undefined') return
  localStorage.removeItem('access_token')
  localStorage.removeItem('refresh_token')
}
