package com.iamservice.postgres;

import com.iamservice.model.vo.RolId;
import com.iamservice.model.vo.UsuarioId;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Repository
public class UsuarioRolesR2dbcAdapter {

    private final DatabaseClient databaseClient;

    public UsuarioRolesR2dbcAdapter(DatabaseClient databaseClient) {
        this.databaseClient = databaseClient;
    }

    public Mono<Void> save(UsuarioId usuarioId, RolId rolId) {
        return databaseClient.sql("""
                INSERT INTO usuario_roles (usuario_id, rol_id)
                VALUES (:usuarioId, :rolId)
                ON CONFLICT DO NOTHING
                """)
                .bind("usuarioId", usuarioId.value())
                .bind("rolId", rolId.value())
                .then();
    }

    public Mono<Void> delete(UsuarioId usuarioId, RolId rolId) {
        return databaseClient.sql("""
                DELETE FROM usuario_roles
                WHERE usuario_id = :usuarioId AND rol_id = :rolId
                """)
                .bind("usuarioId", usuarioId.value())
                .bind("rolId", rolId.value())
                .then();
    }

    public Flux<RolId> findRolesByUsuarioId(UsuarioId usuarioId) {
        return databaseClient.sql("""
                SELECT rol_id FROM usuario_roles WHERE usuario_id = :usuarioId
                """)
                .bind("usuarioId", usuarioId.value())
                .map((row, meta) -> new RolId(row.get("rol_id", UUID.class)))
                .all();
    }
}
