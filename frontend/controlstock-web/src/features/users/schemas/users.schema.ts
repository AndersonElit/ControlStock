import { z } from 'zod'

import { emailSchema } from '@/lib/validations'

export const createUserSchema = z.object({
  name: z.string().min(2, 'Name must be at least 2 characters'),
  email: emailSchema,
  role: z.enum(['admin', 'manager', 'user']),
})

export const updateUserSchema = createUserSchema.partial().extend({
  status: z.enum(['active', 'inactive']).optional(),
})

export type CreateUserInput = z.infer<typeof createUserSchema>
export type UpdateUserInput = z.infer<typeof updateUserSchema>
