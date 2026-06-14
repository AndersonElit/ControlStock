import { del, get, patch, post } from '@/lib/api/client'

import type { CreateUserInput, UpdateUserInput, User } from '../types/users.types'

const BASE = '/users'

export const usersApi = {
  getAll: (params?: PaginationParams) =>
    get<PaginatedResponse<User>>(BASE, { params }),

  getById: (id: string) => get<User>(`${BASE}/${id}`),

  create: (input: CreateUserInput) => post<User>(BASE, input),

  update: (id: string, input: UpdateUserInput) => patch<User>(`${BASE}/${id}`, input),

  remove: (id: string) => del<void>(`${BASE}/${id}`),
}
