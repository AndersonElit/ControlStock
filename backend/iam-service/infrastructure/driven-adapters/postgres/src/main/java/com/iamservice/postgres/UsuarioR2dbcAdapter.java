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
public class UsuarioR2dbcAdapter implements UsuarioRepository {

    private final DatabaseClient databaseClient;

    public UsuarioR2dbcAdapter(DatabaseClient databaseClient) {
        this.databaseClient = databaseClient;
    }

    @Override
    public Mono<Usuario> save(Usuario usuario) {
        return databaseClient.sql("""
                INSERT INTO usuarios (id, keycloak_sub, email, nombre, estado, created_at, updated_at)
                VALUES (:id, :keycloakSub, :email, :nombre, :estado, :createdAt, :updatedAt)
                ON CONFLICT (id) DO UPDATE SET
                    nombre = EXCLUDED.nombre,
                    estado = EXCLUDED.estado,
                    updated_at = EXCLUDED.updated_at
                RETURNING *
                """)
                .bind("id", usuario.getId().value())
                .bind("keycloakSub", usuario.getKeycloakSub().value())
                .bind("email", usuario.getEmail().value())
                .bind("nombre", usuario.getNombre())
                .bind("estado", usuario.getEstado().name())
                .bind("createdAt", usuario.getCreatedAt())
                .bind("updatedAt", usuario.getUpdatedAt())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Usuario> findById(UsuarioId id) {
        return databaseClient.sql("SELECT * FROM usuarios WHERE id = :id")
                .bind("id", id.value())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Usuario> findByEmail(Email email) {
        return databaseClient.sql("SELECT * FROM usuarios WHERE email = :email")
                .bind("email", email.value())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Mono<Usuario> findByKeycloakSub(KeycloakSub sub) {
        return databaseClient.sql("SELECT * FROM usuarios WHERE keycloak_sub = :sub")
                .bind("sub", sub.value())
                .map(this::mapRow)
                .one();
    }

    @Override
    public Flux<Usuario> findAll() {
        return databaseClient.sql("SELECT * FROM usuarios ORDER BY created_at DESC")
                .map(this::mapRow)
                .all();
    }

    @Override
    public Mono<Boolean> existsByEmail(Email email) {
        return databaseClient.sql("SELECT COUNT(*) FROM usuarios WHERE email = :email")
                .bind("email", email.value())
                .map((row, meta) -> row.get(0, Long.class) > 0)
                .one();
    }

    private Usuario mapRow(io.r2dbc.spi.Row row, io.r2dbc.spi.RowMetadata meta) {
        return Usuario.reconstituir(
                new UsuarioId(row.get("id", UUID.class)),
                new KeycloakSub(row.get("keycloak_sub", String.class)),
                new Email(row.get("email", String.class)),
                row.get("nombre", String.class),
                EstadoUsuario.fromString(row.get("estado", String.class)),
                row.get("created_at", OffsetDateTime.class).toInstant(),
                row.get("updated_at", OffsetDateTime.class).toInstant()
        );
    }
}
