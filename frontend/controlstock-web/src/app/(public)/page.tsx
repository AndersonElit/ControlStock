import Link from 'next/link'

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 p-8">
      <div className="text-center">
        <h1 className="text-4xl font-bold tracking-tight">Welcome</h1>
        <p className="mt-4 text-lg text-muted-foreground">
          Enterprise Next.js Archetype — Feature-Based Architecture
        </p>
      </div>
      <div className="flex gap-4">
        <Link
          href="/login"
          className="rounded-md bg-primary px-6 py-3 text-primary-foreground hover:bg-primary/90"
        >
          Sign in
        </Link>
        <Link
          href="/dashboard"
          className="rounded-md border px-6 py-3 hover:bg-accent"
        >
          Dashboard
        </Link>
      </div>
    </main>
  )
}
