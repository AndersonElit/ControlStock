package com.iamservice.postgres;

import com.iamservice.model.*;
import com.iamservice.model.vo.*;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Repository
public class PermisoR2dbcAdapter implements PermisoRepository {

    private final DatabaseClient databaseClient;

    public PermisoR2dbcAdapter(DatabaseClient databaseClient) {
        this.databaseClient = databaseClient;
    }

    @Override
    public Mono<Permiso> save(Permiso permiso) {
        return databaseClient.sql("""
                INSERT INTO permisos (id, modulo, operacion, descripcion)
                VALUES (:id, :modulo, :operacion, :descripcion)
                ON CONFLICT (modulo, operacion) DO UPDATE SET descripcion = EXCLUDED.descripcion
                RETURNING *
                """)
                .bind("id", permiso.getId().value())
                .bind("modulo", permiso.getModulo())
                .bind("operacion", permiso.getOperacion())
                .bind("descripcion", permiso.getDescripcion())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Permiso> findById(PermisoId id) {
        return databaseClient.sql("SELECT * FROM permisos WHERE id = :id")
                .bind("id", id.value())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Flux<Permiso> findAll() {
        return databaseClient.sql("SELECT * FROM permisos ORDER BY modulo, operacion")
                .map(this::mapRow)
                .all();
    }

    @Override
    public Mono<Boolean> existsByModuloAndOperacion(String modulo, String operacion) {
        return databaseClient.sql(
                "SELECT COUNT(*) FROM permisos WHERE modulo = :modulo AND operacion = :operacion")
                .bind("modulo", modulo)
                .bind("operacion", operacion)
                .map((row, meta) -> row.get(0, Long.class) > 0)
                .one();
    }

    private Permiso mapRow(io.r2dbc.spi.Row row, io.r2dbc.spi.RowMetadata meta) {
        return new Permiso(
                new PermisoId(row.get("id", UUID.class)),
                row.get("modulo", String.class),
                row.get("operacion", String.class),
                row.get("descripcion", String.class)
        );
    }
}
