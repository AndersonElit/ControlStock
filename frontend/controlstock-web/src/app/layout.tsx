import type { Metadata } from 'next'
import { Inter } from 'next/font/google'

import { Providers } from '@/providers'
import '@/styles/globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: {
    template: `%s | controlstock-web`,
    default: 'controlstock-web',
  },
  description: 'Enterprise-grade Next.js application',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}
