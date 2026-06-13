// ============================================================
// ControlStock — Read Model MongoDB — Artefacto de Diseño
// Proyecto: ControlStock | Etapa: Diseño Técnico del SDLC
//
// Base de datos: controlstock_readmodel (MongoDB 7)
// Propósito: Read model CQRS proyectado por los microservicios
// operacionales mediante sus projection consumers Kafka.
// Cada servicio es el escritor exclusivo de sus propias colecciones:
//   - inventory-service  → kardex, movimientos, stock
//   - catalog-service    → productos
//   - supplier-service   → proveedores
//
// El ETL (report-etl-service / Spark) lee exclusivamente de
// este read model vía Spark MongoDB Connector.
// ============================================================

// ─── Colección: stock ─────────────────────────────────────────
// Escritor: inventory-service (projection consumer)
// Propósito: Estado actual de stock por producto para dashboard y consultas rápidas

db.createCollection("stock", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["productoId", "stockActual", "updatedAt"],
      properties: {
        _id: { bsonType: "objectId" },
        productoId: {
          bsonType: "string",
          description: "UUID del producto (referencia a catalog)"
        },
        codigoProducto: {
          bsonType: "string",
          description: "Código de producto desnormalizado para queries rápidas"
        },
        nombreProducto: {
          bsonType: "string"
        },
        categoriaId: {
          bsonType: "string"
        },
        nombreCategoria: {
          bsonType: "string"
        },
        stockActual: {
          bsonType: "double",
          minimum: 0,
          description: "Stock disponible actual"
        },
        stockMinimo: {
          bsonType: "double",
          minimum: 0
        },
        stockMaximo: {
          bsonType: "double",
          minimum: 0
        },
        bajominimo: {
          bsonType: "bool",
          description: "Flag calculado: stockActual <= stockMinimo"
        },
        updatedAt: {
          bsonType: "date",
          description: "Timestamp UTC de la última proyección"
        }
      }
    }
  }
});

db.stock.createIndex({ productoId: 1 }, { unique: true });
db.stock.createIndex({ categoriaId: 1 });
db.stock.createIndex({ bajominimo: 1 });
db.stock.createIndex({ stockActual: 1 });

// ─── Colección: movimientos ────────────────────────────────────
// Escritor: inventory-service (projection consumer)
// Propósito: Proyección de movimientos para consultas históricas y ETL de reportería

db.createCollection("movimientos", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["movimientoId", "productoId", "tipo", "cantidad", "fecha", "saldoResultante", "estado", "createdAt"],
      properties: {
        _id: { bsonType: "objectId" },
        movimientoId: {
          bsonType: "string",
          description: "UUID del inventory_movements en PostgreSQL"
        },
        productoId: {
          bsonType: "string"
        },
        codigoProducto: {
          bsonType: "string"
        },
        nombreProducto: {
          bsonType: "string"
        },
        categoriaId: {
          bsonType: "string"
        },
        tipo: {
          bsonType: "string",
          enum: ["ENTRADA", "SALIDA", "AJUSTE"],
          description: "Tipo de movimiento"
        },
        cantidad: {
          bsonType: "double"
        },
        referenciaDocumento: {
          bsonType: "string"
        },
        fecha: {
          bsonType: "date"
        },
        saldoResultante: {
          bsonType: "double",
          minimum: 0
        },
        estado: {
          bsonType: "string",
          enum: ["ACTIVO", "ANULADO"]
        },
        usuarioId: {
          bsonType: "string"
        },
        createdAt: {
          bsonType: "date"
        }
      }
    }
  }
});

db.movimientos.createIndex({ movimientoId: 1 }, { unique: true });
db.movimientos.createIndex({ productoId: 1, fecha: -1 });
db.movimientos.createIndex({ productoId: 1, createdAt: -1 });
db.movimientos.createIndex({ tipo: 1, fecha: -1 });
db.movimientos.createIndex({ categoriaId: 1, fecha: -1 });
db.movimientos.createIndex({ estado: 1 });

// ─── Colección: kardex ─────────────────────────────────────────
// Escritor: inventory-service (projection consumer)
// Propósito: Vista Kardex por producto con entradas cronológicas y saldo acumulado.
// Un documento por producto con array de entradas (modelo embebido para consultas de Kardex).

db.createCollection("kardex", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["productoId", "entradas", "saldoActual", "updatedAt"],
      properties: {
        _id: { bsonType: "objectId" },
        productoId: {
          bsonType: "string",
          description: "UUID del producto — clave de acceso principal"
        },
        codigoProducto: {
          bsonType: "string"
        },
        nombreProducto: {
          bsonType: "string"
        },
        saldoActual: {
          bsonType: "double",
          minimum: 0
        },
        totalEntradas: {
          bsonType: "int"
        },
        updatedAt: {
          bsonType: "date"
        },
        entradas: {
          bsonType: "array",
          description: "Últimas N entradas del Kardex (ventana deslizante; historial completo en colección movimientos)",
          items: {
            bsonType: "object",
            required: ["movimientoId", "tipo", "cantidad", "saldoResultante", "fecha"],
            properties: {
              movimientoId: { bsonType: "string" },
              tipo: { bsonType: "string", enum: ["ENTRADA", "SALIDA", "AJUSTE"] },
              cantidad: { bsonType: "double" },
              saldoResultante: { bsonType: "double" },
              referenciaDocumento: { bsonType: "string" },
              fecha: { bsonType: "date" },
              estado: { bsonType: "string", enum: ["ACTIVO", "ANULADO"] }
            }
          }
        }
      }
    }
  }
});

db.kardex.createIndex({ productoId: 1 }, { unique: true });
db.kardex.createIndex({ codigoProducto: 1 });

// ─── Colección: productos ──────────────────────────────────────
// Escritor: catalog-service (projection consumer)
// Propósito: Proyección desnormalizada del catálogo para el ETL de reportería
// y vistas de dashboard sin consultar PostgreSQL operacional

db.createCollection("productos", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["productoId", "codigo", "nombre", "categoriaId", "estado", "updatedAt"],
      properties: {
        _id: { bsonType: "objectId" },
        productoId: {
          bsonType: "string",
          description: "UUID del productos en PostgreSQL"
        },
        codigo: {
          bsonType: "string"
        },
        nombre: {
          bsonType: "string"
        },
        descripcion: {
          bsonType: "string"
        },
        categoriaId: {
          bsonType: "string"
        },
        nombreCategoria: {
          bsonType: "string"
        },
        stockMinimo: {
          bsonType: "double"
        },
        stockMaximo: {
          bsonType: "double"
        },
        estado: {
          bsonType: "string",
          enum: ["ACTIVO", "INACTIVO"]
        },
        updatedAt: {
          bsonType: "date"
        }
      }
    }
  }
});

db.productos.createIndex({ productoId: 1 }, { unique: true });
db.productos.createIndex({ codigo: 1 }, { unique: true });
db.productos.createIndex({ categoriaId: 1 });
db.productos.createIndex({ estado: 1 });

// ─── Colección: proveedores ────────────────────────────────────
// Escritor: supplier-service (projection consumer)
// Propósito: Proyección del catálogo de proveedores para el ETL
// del reporte proveedores-actividad

db.createCollection("proveedores", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["proveedorId", "nombre", "estado", "updatedAt"],
      properties: {
        _id: { bsonType: "objectId" },
        proveedorId: {
          bsonType: "string",
          description: "UUID del suppliers en PostgreSQL"
        },
        nombre: {
          bsonType: "string"
        },
        identificacionFiscal: {
          bsonType: "string"
        },
        metodoIntegracion: {
          bsonType: "string",
          enum: ["REST", "ARCHIVO"]
        },
        estado: {
          bsonType: "string",
          enum: ["ACTIVO", "INACTIVO"]
        },
        totalMovimientos: {
          bsonType: "int",
          description: "Contador desnormalizado de movimientos asociados al proveedor"
        },
        updatedAt: {
          bsonType: "date"
        }
      }
    }
  }
});

db.proveedores.createIndex({ proveedorId: 1 }, { unique: true });
db.proveedores.createIndex({ estado: 1 });
