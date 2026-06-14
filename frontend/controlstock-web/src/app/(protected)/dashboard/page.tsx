import type { Metadata } from 'next'

import { DashboardStats } from '@/features/dashboard/components/dashboard-stats'

export const metadata: Metadata = { title: 'Dashboard' }

export default function DashboardPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <p className="text-muted-foreground">Welcome back</p>
      </div>
      <DashboardStats />
    </div>
  )
}
