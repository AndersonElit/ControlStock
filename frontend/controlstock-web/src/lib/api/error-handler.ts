import type { AxiosError } from 'axios'

import type { ApiError } from '@/types/api.types'

export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly status: number,
    public readonly details?: Record<string, string[]>
  ) {
    super(message)
    this.name = 'AppError'
  }
}

export function handleApiError(error: AxiosError): AppError {
  const apiError = error.response?.data as ApiError | undefined

  if (apiError) {
    return new AppError(
      apiError.message ?? 'An unexpected error occurred',
      apiError.code ?? 'UNKNOWN_ERROR',
      error.response?.status ?? 500,
      apiError.details
    )
  }

  if (error.request) {
    return new AppError('Network error — please check your connection', 'NETWORK_ERROR', 0)
  }

  return new AppError(error.message, 'CLIENT_ERROR', 0)
}

export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError
}
