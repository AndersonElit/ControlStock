declare global {
  type Nullable<T> = T | null
  type Optional<T> = T | undefined
  type Maybe<T> = T | null | undefined
  type ID = string
  type Timestamp = string

  interface PaginationParams {
    page: number
    limit: number
  }

  interface PaginatedResponse<T> {
    data: T[]
    total: number
    page: number
    limit: number
    totalPages: number
  }
}

export {}
