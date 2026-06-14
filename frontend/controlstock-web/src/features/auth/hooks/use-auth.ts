'use client'

import { useMutation } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

import { ROUTES } from '@/lib/constants'

import { authService } from '../services/auth.service'
import { useAuthStore } from '../store/auth.store'
import type { LoginCredentials } from '../types/auth.types'

export function useAuth() {
  const router = useRouter()
  const { setUser, clearAuth, user, isAuthenticated } = useAuthStore()

  const loginMutation = useMutation({
    mutationFn: (credentials: LoginCredentials) => authService.login(credentials),
    onSuccess: ({ user, tokens }) => {
      setUser(user, tokens.accessToken)
      toast.success(`Welcome back, ${user.name}!`)
      router.push(ROUTES.DASHBOARD)
    },
    onError: (error: Error) => {
      toast.error(error.message)
    },
  })

  const logoutMutation = useMutation({
    mutationFn: authService.logout,
    onSuccess: () => {
      clearAuth()
      router.push(ROUTES.LOGIN)
    },
  })

  return {
    user,
    isAuthenticated,
    login: loginMutation.mutate,
    logout: logoutMutation.mutate,
    isLoggingIn: loginMutation.isPending,
    isLoggingOut: logoutMutation.isPending,
  }
}
