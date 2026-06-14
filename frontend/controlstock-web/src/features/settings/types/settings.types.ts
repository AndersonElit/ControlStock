export interface AppSettings {
  theme: 'light' | 'dark' | 'system'
  language: string
  notifications: NotificationSettings
}

export interface NotificationSettings {
  email: boolean
  push: boolean
  marketing: boolean
}
