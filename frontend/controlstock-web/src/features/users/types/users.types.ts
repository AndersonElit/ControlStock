export interface User {
  id: string
  name: string
  email: string
  role: string
  status: 'active' | 'inactive'
  createdAt: string
  updatedAt: string
}

export interface CreateUserInput {
  name: string
  email: string
  role: string
}

export interface UpdateUserInput extends Partial<CreateUserInput> {
  status?: User['status']
}
