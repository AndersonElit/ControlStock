package com.example.reportetlservice.domain.model

/** Regla de integridad declarativa. `rule` admite p.ej. "NOT_NULL", "UNIQUE", "RANGE:0:100". */
final case class IntegrityRule(column: String, rule: String)
