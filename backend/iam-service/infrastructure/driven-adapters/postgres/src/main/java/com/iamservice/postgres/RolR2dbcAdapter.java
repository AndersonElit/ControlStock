package com.iamservice.postgres;

import com.iamservice.model.*;
import com.iamservice.model.vo.*;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.UUID;

@Repository
public class RolR2dbcAdapter implements RolRepository {

    private final DatabaseClient databaseClient;

    public RolR2dbcAdapter(DatabaseClient databaseClient) {
        this.databaseClient = databaseClient;
    }

    @Override
    public Mono<Rol> save(Rol rol) {
        return databaseClient.sql("""
                INSERT INTO roles (id, nombre, descripcion, created_at)
                VALUES (:id, :nombre, :descripcion, :createdAt)
                ON CONFLICT (id) DO UPDATE SET
                    nombre = EXCLUDED.nombre,
                    descripcion = EXCLUDED.descripcion
                RETURNING *
                """)
                .bind("id", rol.getId().value())
                .bind("nombre", rol.getNombre())
                .bind("descripcion", rol.getDescripcion())
                .bind("createdAt", rol.getCreatedAt())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Rol> findById(RolId id) {
        return databaseClient.sql("SELECT * FROM roles WHERE id = :id")
                .bind("id", id.value())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Rol> findByNombre(String nombre) {
        return databaseClient.sql("SELECT * FROM roles WHERE nombre = :nombre")
                .bind("nombre", nombre)
                .map(this::mapRow)
                .one();
    }

    @Override
    public Flux<Rol> findAll() {
        return databaseClient.sql("SELECT * FROM roles ORDER BY nombre")
                .map(this::mapRow)
                .all();
    }

    @Override
    public Mono<Boolean> existsByNombre(String nombre) {
        return databaseClient.sql("SELECT COUNT(*) FROM roles WHERE nombre = :nombre")
                .bind("nombre", nombre)
                .map((row, meta) -> row.get(0, Long.class) > 0)
                .one();
    }

    private Rol mapRow(io.r2dbc.spi.Row row, io.r2dbc.spi.RowMetadata meta) {
        return new Rol(
                new RolId(row.get("id", UUID.class)),
                row.get("nombre", String.class),
                row.get("descripcion", String.class),
                row.get("created_at", OffsetDateTime.class).toInstant()
        );
    }
}
