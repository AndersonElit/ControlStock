import { describe, it, expect } from 'vitest'

import { capitalize, truncate, cn } from '@/lib/utils'

describe('utils', () => {
  describe('capitalize', () => {
    it('capitalizes the first letter', () => {
      expect(capitalize('hello')).toBe('Hello')
    })
  })

  describe('truncate', () => {
    it('truncates long strings', () => {
      expect(truncate('hello world', 5)).toBe('hello...')
    })

    it('does not truncate short strings', () => {
      expect(truncate('hi', 5)).toBe('hi')
    })
  })

  describe('cn', () => {
    it('merges class names', () => {
      expect(cn('foo', 'bar')).toBe('foo bar')
    })
  })
})
