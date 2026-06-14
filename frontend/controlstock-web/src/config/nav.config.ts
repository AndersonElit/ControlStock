import type { LucideIcon } from 'lucide-react'
import { LayoutDashboard, Users, Settings } from 'lucide-react'

import { ROUTES } from '@/lib/constants'

export interface NavItem {
  href: string
  label: string
  icon: LucideIcon
  roles?: string[]
}

export const mainNav: NavItem[] = [
  { href: ROUTES.DASHBOARD, label: 'Dashboard', icon: LayoutDashboard },
  { href: ROUTES.USERS, label: 'Users', icon: Users, roles: ['admin'] },
  { href: ROUTES.SETTINGS, label: 'Settings', icon: Settings },
]
