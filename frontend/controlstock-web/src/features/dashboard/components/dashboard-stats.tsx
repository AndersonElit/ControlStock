import { Users, TrendingUp, Activity, DollarSign } from 'lucide-react'

const stats = [
  { label: 'Total Users', value: '—', icon: Users, delta: '+0%' },
  { label: 'Revenue', value: '—', icon: DollarSign, delta: '+0%' },
  { label: 'Active Sessions', value: '—', icon: Activity, delta: '+0%' },
  { label: 'Growth', value: '—', icon: TrendingUp, delta: '+0%' },
]

export function DashboardStats() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {stats.map(({ label, value, icon: Icon, delta }) => (
        <div key={label} className="rounded-lg border bg-card p-6">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-muted-foreground">{label}</p>
            <Icon className="h-4 w-4 text-muted-foreground" />
          </div>
          <p className="mt-2 text-3xl font-bold">{value}</p>
          <p className="mt-1 text-xs text-muted-foreground">{delta} from last month</p>
        </div>
      ))}
    </div>
  )
}
