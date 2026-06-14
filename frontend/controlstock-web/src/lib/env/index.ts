import { z } from 'zod'

const envSchema = z.object({
  NEXT_PUBLIC_APP_URL: z.preprocess(
    (v) => (v && String(v).trim()) || 'http://localhost:3000',
    z.string().url()
  ),
  NEXT_PUBLIC_APP_NAME: z.string().min(1).default('App'),
  NEXT_PUBLIC_APP_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  NEXT_PUBLIC_API_URL: z.preprocess(
    (v) => (v && String(v).trim()) || 'http://localhost:8000',
    z.string().url()
  ),
  NEXT_PUBLIC_ENABLE_ANALYTICS: z
    .string()
    .transform((v) => v === 'true')
    .default('false'),
  NEXT_PUBLIC_ENABLE_DEBUG: z
    .string()
    .transform((v) => v === 'true')
    .default('false'),
})

const parsed = envSchema.safeParse(process.env)

if (!parsed.success) {
  console.error('❌ Invalid environment variables:', parsed.error.flatten().fieldErrors)
  throw new Error('Invalid environment variables — check .env.local')
}

export const env = parsed.data

export const isDev = env.NEXT_PUBLIC_APP_ENV === 'development'
export const isProd = env.NEXT_PUBLIC_APP_ENV === 'production'
