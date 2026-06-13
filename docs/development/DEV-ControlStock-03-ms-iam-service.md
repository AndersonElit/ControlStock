# Etapa 3a — Microservicio: IAM Service (BC-01)

## Tabla de Contenidos

1. [Contexto y Responsabilidad](#contexto-y-responsabilidad)
2. [Prerrequisitos](#prerrequisitos)
3. [Ciclo de Desarrollo Incremental en K3s VPS dev](#ciclo-de-desarrollo-incremental-en-k3s-vps-dev)
4. [Capa de Dominio](#capa-de-dominio)
5. [Capa de Aplicación](#capa-de-aplicación)
6. [Capa de Infraestructura](#capa-de-infraestructura)
7. [API REST](#api-rest)
8. [Especificación TDD por Capa (Red-Green-Refactor)](#especificación-tdd-por-capa-red-green-refactor)
9. [Criterios de Aceptación](#criterios-de-aceptación)

---

## Contexto y Responsabilidad

El **IAM Service** (Bounded Context BC-01) es el microservicio responsable de la gestión del ciclo de vida de identidades y accesos en ControlStock. Es el **primer microservicio en implementarse** porque todos los demás servicios dependen de Keycloak para la validación de tokens JWT.

### Responsabilidades del servicio

| Responsabilidad | Descripción |
|----------------|-------------|
| **Gestión de usuarios Keycloak** | Crear, modificar y desactivar usuarios en el realm `controlstock` de Keycloak mediante la API Admin REST |
| **Proyección local** | Mantener la tabla `usuarios` en `controlstock_iam` sincronizada con Keycloak (fuente de verdad: Keycloak; proyección: PostgreSQL local) |
| **Gestión de roles RBAC** | Crear y listar roles con granularidad de módulo/operación |
| **Gestión de permisos** | Crear y listar permisos asociados a módulos y operaciones del sistema |
| **Asignación/revocación de roles** | Asignar y revocar roles a usuarios, reflejando el cambio tanto en Keycloak como en la tabla `usuario_roles` |

### Lo que el servicio NO hace

| Restricción | Justificación |
|-------------|---------------|
| No publica eventos Kafka | No tiene outbox; otros servicios validan tokens directamente con Keycloak JWKS |
| No participa en sagas | No hay flujos distribuidos que involucren IAM |
| No tiene dependencias REST de otros servicios de dominio | IAM es el servicio raíz de la jerarquía de dependencias |
| No emite eventos de dominio a otros BCs | La identidad se valida vía JWT estándar |

### Bounded Context BC-01

```
┌─────────────────────────────────────────────────────┐
│                   IAM Service (BC-01)               │
│                                                     │
│  ┌───────────┐  ┌──────────┐  ┌────────────────┐  │
│  │  usuarios │  │  roles   │  │   permisos     │  │
│  └───────────┘  └──────────┘  └────────────────┘  │
│  ┌─────────────────────────────────────────────┐   │
│  │          usuario_roles / rol_permisos       │   │
│  └─────────────────────────────────────────────┘   │
│                        │                            │
│            ┌───────────▼───────────┐               │
│            │  KeycloakGateway      │               │
│            │  (Admin REST API)     │               │
└────────────┴───────────────────────┴───────────────┘
                         │
                         ▼
             ┌───────────────────────┐
             │    Keycloak 24        │
             │    realm: controlstock│
             └───────────────────────┘
```

### Base de datos

- **PostgreSQL 16** — schema `controlstock_iam`
- **Tecnología de acceso**: Spring Data R2DBC (reactivo, sin bloqueo)
- **Migraciones**: Flyway gestionadas desde `controlstock-migrations`

---

## Prerrequisitos

Las siguientes etapas y condiciones deben estar satisfechas antes de comenzar la implementación:

| Prerrequisito | Documento de referencia | Verificación |
|--------------|------------------------|-------------|
| Etapa 0 — Infraestructura base completa | `DEV-ControlStock-00-infrastructure.md` | K3s corriendo, namespaces creados |
| Etapa 0c — Observabilidad configurada | `DEV-ControlStock-0c-observability.md` | Prometheus + Grafana activos |
| Etapa 1 — Bases de datos aprovisionadas | `DEV-ControlStock-01-databases.md` | PostgreSQL `controlstock_iam` con tablas migradas |
| Etapa 2 — Scaffold generado | `DEV-ControlStock-02-scaffold.md` | Proyecto Maven generado con estructura hexagonal |
| Etapa 2b — Pipeline CI/CD configurado | `DEV-ControlStock-02b-cicd.md` | Job `iam-service` activo en Jenkins; ArgoCD app creada |
| Keycloak 24 corriendo | Etapa 0 | Realm `controlstock` configurado; Admin REST API accesible |

### Verificación de prerrequisitos

```bash
# Verificar PostgreSQL y schema
kubectl exec -n databases deploy/postgresql -- psql \
  -U controlstock_iam -d controlstock_iam \
  -c "\dt" | grep -E "roles|permisos|usuarios"

# Verificar Keycloak realm
curl -s "http://<VPS_IP>:8180/realms/controlstock/.well-known/openid-configuration" \
  | jq '.issuer'
# Salida: "http://<VPS_IP>:8180/realms/controlstock"

# Verificar job Jenkins
curl -s "http://<VPS_IP>:8080/job/iam-service/api/json" \
  --user "admin:<password>" | jq '.name'
```

---

## Ciclo de Desarrollo Incremental en K3s VPS dev

El desarrollo sigue un ciclo **TDD → commit → CI/CD → verificación en K3s** que garantiza que cada incremento está validado antes de avanzar al siguiente.

### Diagrama del ciclo incremental

```
┌─────────────────────────────────────────────────────┐
│              Ciclo de Desarrollo TDD                │
│                                                     │
│  1. Escribir test RED (falla esperada)              │
│         │                                           │
│         ▼                                           │
│  2. Implementar mínimo código GREEN                 │
│         │                                           │
│         ▼                                           │
│  3. REFACTOR — mejorar diseño                       │
│         │                                           │
│         ▼                                           │
│  4. git push → Gitea webhook                        │
│         │                                           │
│         ▼                                           │
│  5. Jenkins pipeline (build+test+scan+image)        │
│         │                                           │
│         ▼                                           │
│  6. bumpImageTag → ArgoCD sync                      │
│         │                                           │
│         ▼                                           │
│  7. Verificar /actuator/health en K3s               │
│         │                                           │
│         ▼                                           │
│  8. Siguiente incremento ──────────────────────┐   │
│                                                │   │
└────────────────────────────────────────────────┘   │
                                                      │
         Condición mínima para primer deploy:         │
         ┌────────────────────────────────────┐       │
         │ - Entidades de dominio compiladas  │       │
         │ - Contexto Spring arranca sin error│       │
         │ - GET /actuator/health → 200       │       │
         └────────────────────────────────────┘       │
```

### Orden de implementación incremental

| Incremento | Capa | Contenido | Condición de avance |
|-----------|------|-----------|-------------------|
| **I-1** | Dominio | Entidades, VOs, puertos | Tests dominio GREEN |
| **I-2** | Aplicación | Use cases (CrearUsuario, InactivarUsuario) | Tests aplicación GREEN; dominio refactorizado |
| **I-3** | Infraestructura | R2DBC adapters (roles, permisos, usuarios) | Tests Testcontainers GREEN |
| **I-4** | Infraestructura | KeycloakAdapter (Admin REST Client) | Tests Testcontainers GREEN con Keycloak WireMock |
| **I-5** | Infraestructura | Spring Security (JWT RS256 JWKS) | Tests de seguridad GREEN |
| **I-6** | Aplicación | Use cases (AsignarRol, RevocarRol, Listar) | Tests aplicación GREEN |
| **I-7** | API REST | Endpoints completos + @ExceptionHandler | Tests @WebFluxTest GREEN |
| **I-8** | Integración | Tests E2E en K3s (Postman/REST Assured) | Suite de humo GREEN |

---

## Capa de Dominio

La capa de dominio es **pura** (sin dependencias de frameworks) e implementa todas las invariantes del negocio.

### Entidades

#### `Usuario`

```java
// src/main/java/com/controlstock/iam/domain/model/Usuario.java
public class Usuario {
    private final UsuarioId id;
    private final KeycloakSub keycloakSub;
    private final Email email;
    private String nombre;
    private EstadoUsuario estado;
    private final Instant createdAt;
    private Instant updatedAt;
    private final Set<RolId> roles;

    // Invariante: estado solo puede ser ACTIVO o INACTIVO
    // Invariante: keycloakSub es inmutable una vez asignado
    // Invariante: email es inmutable una vez asignado

    public void inactivar() {
        if (this.estado == EstadoUsuario.INACTIVO) {
            throw new UsuarioYaInactivoException(this.id);
        }
        this.estado = EstadoUsuario.INACTIVO;
        this.updatedAt = Instant.now();
    }

    public void asignarRol(RolId rolId) {
        if (this.estado == EstadoUsuario.INACTIVO) {
            throw new UsuarioInactivoException(this.id);
        }
        this.roles.add(rolId);
    }

    public void revocarRol(RolId rolId) {
        if (!this.roles.contains(rolId)) {
            throw new RolNoAsignadoException(rolId, this.id);
        }
        this.roles.remove(rolId);
    }
}
```

#### `Rol`

```java
// src/main/java/com/controlstock/iam/domain/model/Rol.java
public class Rol {
    private final RolId id;
    private final String nombre;      // VARCHAR(50) UNIQUE
    private final String descripcion;
    private final Instant createdAt;
    private Set<PermisoId> permisos;
}
```

#### `Permiso`

```java
// src/main/java/com/controlstock/iam/domain/model/Permiso.java
public class Permiso {
    private final PermisoId id;
    private final String modulo;       // e.g. "INVENTORY"
    private final String operacion;   // e.g. "READ"
    private final String descripcion;
    // Invariante: (modulo, operacion) UNIQUE
}
```

### Value Objects

| Value Object | Validaciones | Clase |
|-------------|-------------|-------|
| `KeycloakSub` | No nulo, no vacío, máx 200 chars, inmutable | `com.controlstock.iam.domain.vo.KeycloakSub` |
| `Email` | Formato RFC 5322, no nulo, máx 200 chars, lowercase normalizado | `com.controlstock.iam.domain.vo.Email` |
| `UsuarioId` | UUID no nulo | `com.controlstock.iam.domain.vo.UsuarioId` |
| `RolId` | UUID no nulo | `com.controlstock.iam.domain.vo.RolId` |
| `PermisoId` | UUID no nulo | `com.controlstock.iam.domain.vo.PermisoId` |

```java
// Ejemplo: Email Value Object
public record Email(String value) {
    public Email {
        Objects.requireNonNull(value, "email no puede ser nulo");
        String normalized = value.strip().toLowerCase();
        if (!normalized.matches("^[^@]+@[^@]+\\.[^@]+$")) {
            throw new EmailInvalidoException(value);
        }
        if (normalized.length() > 200) {
            throw new EmailDemasiadoLargoException(value);
        }
        value = normalized;
    }
}
```

### Enumeración `EstadoUsuario`

```java
public enum EstadoUsuario {
    ACTIVO, INACTIVO;

    public static EstadoUsuario fromString(String value) {
        return Arrays.stream(values())
            .filter(e -> e.name().equalsIgnoreCase(value))
            .findFirst()
            .orElseThrow(() -> new EstadoUsuarioInvalidoException(value));
    }
}
```

### Puertos (interfaces de dominio)

```java
// Puerto: UsuarioRepository
public interface UsuarioRepository {
    Mono<Usuario> save(Usuario usuario);
    Mono<Usuario> findById(UsuarioId id);
    Mono<Usuario> findByEmail(Email email);
    Mono<Usuario> findByKeycloakSub(KeycloakSub sub);
    Flux<Usuario> findAll();
    Mono<Boolean> existsByEmail(Email email);
}

// Puerto: RolRepository
public interface RolRepository {
    Mono<Rol> save(Rol rol);
    Mono<Rol> findById(RolId id);
    Mono<Rol> findByNombre(String nombre);
    Flux<Rol> findAll();
    Mono<Boolean> existsByNombre(String nombre);
}

// Puerto: PermisoRepository
public interface PermisoRepository {
    Mono<Permiso> save(Permiso permiso);
    Mono<Permiso> findById(PermisoId id);
    Flux<Permiso> findAll();
    Mono<Boolean> existsByModuloAndOperacion(String modulo, String operacion);
}

// Puerto: KeycloakGateway
public interface KeycloakGateway {
    Mono<KeycloakSub> crearUsuario(String email, String nombre, String password);
    Mono<Void> actualizarUsuario(KeycloakSub sub, String nombre);
    Mono<Void> desactivarUsuario(KeycloakSub sub);
    Mono<Void> asignarRol(KeycloakSub sub, String rolNombre);
    Mono<Void> revocarRol(KeycloakSub sub, String rolNombre);
}
```

### Excepciones de dominio

| Excepción | Trigger |
|-----------|---------|
| `UsuarioYaInactivoException` | Llamar `inactivar()` sobre un usuario ya INACTIVO |
| `UsuarioInactivoException` | Intentar asignar rol a usuario INACTIVO |
| `RolNoAsignadoException` | Revocar rol que el usuario no tiene asignado |
| `EmailInvalidoException` | Formato de email inválido en VO |
| `EmailDemasiadoLargoException` | Email > 200 caracteres |
| `EstadoUsuarioInvalidoException` | String que no mapea a ACTIVO/INACTIVO |
| `EmailDuplicadoException` | Email ya registrado en el sistema |
| `KeycloakSubDuplicadoException` | keycloak_sub ya registrado |

---

## Capa de Aplicación

### Use Cases

#### `CrearUsuarioUseCase`

```java
@UseCase
@Transactional
public class CrearUsuarioUseCase {

    private final UsuarioRepository usuarioRepository;
    private final RolRepository rolRepository;
    private final KeycloakGateway keycloakGateway;

    public Mono<UsuarioDTO> ejecutar(CrearUsuarioCommand command) {
        return usuarioRepository.existsByEmail(new Email(command.email()))
            .flatMap(exists -> {
                if (exists) return Mono.error(new EmailDuplicadoException(command.email()));
                return keycloakGateway.crearUsuario(
                    command.email(), command.nombre(), command.passwordTemporal()
                );
            })
            .flatMap(sub -> {
                Usuario usuario = Usuario.crear(sub, new Email(command.email()), command.nombre());
                return usuarioRepository.save(usuario);
            })
            .map(UsuarioMapper::toDTO);
    }
}
```

#### `InactivarUsuarioUseCase`

```java
@UseCase
@Transactional
public class InactivarUsuarioUseCase {

    private final UsuarioRepository usuarioRepository;
    private final KeycloakGateway keycloakGateway;

    public Mono<Void> ejecutar(UsuarioId id) {
        return usuarioRepository.findById(id)
            .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(id)))
            .flatMap(usuario -> {
                usuario.inactivar();  // lanza UsuarioYaInactivoException si ya inactivo
                return keycloakGateway.desactivarUsuario(usuario.getKeycloakSub())
                    .then(usuarioRepository.save(usuario));
            })
            .then();
    }
}
```

#### `AsignarRolUseCase`

```java
@UseCase
@Transactional
public class AsignarRolUseCase {

    private final UsuarioRepository usuarioRepository;
    private final RolRepository rolRepository;
    private final KeycloakGateway keycloakGateway;

    public Mono<Void> ejecutar(UsuarioId usuarioId, RolId rolId) {
        return Mono.zip(
            usuarioRepository.findById(usuarioId)
                .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(usuarioId))),
            rolRepository.findById(rolId)
                .switchIfEmpty(Mono.error(new RolNoEncontradoException(rolId)))
        ).flatMap(tuple -> {
            Usuario usuario = tuple.getT1();
            Rol rol = tuple.getT2();
            usuario.asignarRol(rolId);  // lanza UsuarioInactivoException si inactivo
            return keycloakGateway.asignarRol(usuario.getKeycloakSub(), rol.getNombre())
                .then(usuarioRepository.save(usuario));
        }).then();
    }
}
```

#### `RevocarRolUseCase`

```java
@UseCase
@Transactional
public class RevocarRolUseCase {

    private final UsuarioRepository usuarioRepository;
    private final RolRepository rolRepository;
    private final KeycloakGateway keycloakGateway;

    public Mono<Void> ejecutar(UsuarioId usuarioId, RolId rolId) {
        return Mono.zip(
            usuarioRepository.findById(usuarioId)
                .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(usuarioId))),
            rolRepository.findById(rolId)
                .switchIfEmpty(Mono.error(new RolNoEncontradoException(rolId)))
        ).flatMap(tuple -> {
            Usuario usuario = tuple.getT1();
            Rol rol = tuple.getT2();
            usuario.revocarRol(rolId);  // lanza RolNoAsignadoException si no tiene el rol
            return keycloakGateway.revocarRol(usuario.getKeycloakSub(), rol.getNombre())
                .then(usuarioRepository.save(usuario));
        }).then();
    }
}
```

#### `ListarUsuariosUseCase`

```java
@UseCase
public class ListarUsuariosUseCase {

    private final UsuarioRepository usuarioRepository;

    public Flux<UsuarioDTO> ejecutar() {
        return usuarioRepository.findAll()
            .map(UsuarioMapper::toDTO);
    }
}
```

### DTOs de Aplicación

#### Comandos (entrada)

```java
// Crear usuario
public record CrearUsuarioCommand(
    String email,
    String nombre,
    String passwordTemporal
) {}

// Crear rol
public record CrearRolCommand(
    String nombre,
    String descripcion
) {}

// Asignar/revocar rol
public record AsignarRolCommand(
    UUID usuarioId,
    UUID rolId
) {}
```

#### DTOs de respuesta

```java
// UsuarioDTO
public record UsuarioDTO(
    UUID id,
    String keycloakSub,
    String email,
    String nombre,
    String estado,
    Instant createdAt,
    Instant updatedAt,
    List<RolResumenDTO> roles
) {}

// RolDTO
public record RolDTO(
    UUID id,
    String nombre,
    String descripcion,
    Instant createdAt
) {}

// PermisoDTO
public record PermisoDTO(
    UUID id,
    String modulo,
    String operacion,
    String descripcion
) {}

// RolResumenDTO (para anidado en UsuarioDTO)
public record RolResumenDTO(
    UUID id,
    String nombre
) {}
```

### Mapper

```java
@Component
public class UsuarioMapper {
    public static UsuarioDTO toDTO(Usuario usuario) {
        return new UsuarioDTO(
            usuario.getId().value(),
            usuario.getKeycloakSub().value(),
            usuario.getEmail().value(),
            usuario.getNombre(),
            usuario.getEstado().name(),
            usuario.getCreatedAt(),
            usuario.getUpdatedAt(),
            Collections.emptyList()  // roles se cargan por separado
        );
    }
}
```

---

## Capa de Infraestructura

### Adaptadores R2DBC (PostgreSQL)

#### `UsuarioR2dbcAdapter`

```java
@Repository
@RequiredArgsConstructor
public class UsuarioR2dbcAdapter implements UsuarioRepository {

    private final DatabaseClient databaseClient;

    @Override
    public Mono<Usuario> save(Usuario usuario) {
        // INSERT ... ON CONFLICT (id) DO UPDATE ...
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
            // ... otros binds
            .map(row -> UsuarioRowMapper.map(row))
            .one();
    }

    @Override
    public Mono<Usuario> findById(UsuarioId id) {
        return databaseClient.sql("SELECT * FROM usuarios WHERE id = :id")
            .bind("id", id.value())
            .map(row -> UsuarioRowMapper.map(row))
            .one()
            .switchIfEmpty(Mono.error(new UsuarioNoEncontradoException(id)));
    }

    @Override
    public Mono<Boolean> existsByEmail(Email email) {
        return databaseClient.sql(
            "SELECT COUNT(*) FROM usuarios WHERE email = :email")
            .bind("email", email.value())
            .map(row -> row.get(0, Long.class) > 0)
            .one();
    }

    // ... otros métodos del puerto
}
```

#### Mapeo de filas

```java
public class UsuarioRowMapper {
    public static Usuario map(Row row) {
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
```

#### Adaptadores para tablas de relación

```java
// Adaptador para usuario_roles
@Repository
public class UsuarioRolesR2dbcAdapter {

    private final DatabaseClient databaseClient;

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
            .map(row -> new RolId(row.get("rol_id", UUID.class)))
            .all();
    }
}
```

### Adaptador Keycloak (`KeycloakAdapter`)

```java
@Component
@RequiredArgsConstructor
public class KeycloakAdapter implements KeycloakGateway {

    private final Keycloak keycloakAdminClient;  // keycloak-admin-client
    private final String realm;                   // "controlstock"
    private final WebClient keycloakWebClient;

    @Override
    public Mono<KeycloakSub> crearUsuario(String email, String nombre, String password) {
        return Mono.fromCallable(() -> {
            UserRepresentation user = new UserRepresentation();
            user.setEmail(email);
            user.setFirstName(nombre);
            user.setEnabled(true);
            user.setEmailVerified(false);

            CredentialRepresentation cred = new CredentialRepresentation();
            cred.setType(CredentialRepresentation.PASSWORD);
            cred.setValue(password);
            cred.setTemporary(true);
            user.setCredentials(List.of(cred));

            try (Response response = keycloakAdminClient.realm(realm).users().create(user)) {
                if (response.getStatus() == 409) {
                    throw new EmailDuplicadoEnKeycloakException(email);
                }
                if (response.getStatus() != 201) {
                    throw new KeycloakException("Error al crear usuario: " + response.getStatus());
                }
                String location = response.getHeaderString("Location");
                String userId = location.substring(location.lastIndexOf('/') + 1);
                return new KeycloakSub(userId);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Void> desactivarUsuario(KeycloakSub sub) {
        return Mono.fromRunnable(() -> {
            UserRepresentation user = keycloakAdminClient.realm(realm)
                .users().get(sub.value()).toRepresentation();
            user.setEnabled(false);
            keycloakAdminClient.realm(realm).users().get(sub.value()).update(user);
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }

    @Override
    public Mono<Void> asignarRol(KeycloakSub sub, String rolNombre) {
        return Mono.fromRunnable(() -> {
            RoleRepresentation role = keycloakAdminClient.realm(realm)
                .roles().get(rolNombre).toRepresentation();
            keycloakAdminClient.realm(realm).users().get(sub.value())
                .roles().realmLevel().add(List.of(role));
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }

    @Override
    public Mono<Void> revocarRol(KeycloakSub sub, String rolNombre) {
        return Mono.fromRunnable(() -> {
            RoleRepresentation role = keycloakAdminClient.realm(realm)
                .roles().get(rolNombre).toRepresentation();
            keycloakAdminClient.realm(realm).users().get(sub.value())
                .roles().realmLevel().remove(List.of(role));
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }
}
```

### Spring Security — Validación JWT RS256 (JWKS)

```java
@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {

    @Value("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}")
    private String jwkSetUri;

    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/actuator/health/**", "/actuator/prometheus").permitAll()
                .anyExchange().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwkSetUri(jwkSetUri))
            )
            .build();
    }

    @Bean
    public ReactiveJwtDecoder jwtDecoder() {
        return ReactiveJwtDecoders.fromIssuerLocation(
            "http://keycloak.auth.svc.cluster.local:8080/realms/controlstock"
        );
    }
}
```

### Configuración `application.yml`

```yaml
spring:
  application:
    name: iam-service
  r2dbc:
    url: r2dbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:controlstock_iam}
    username: ${DB_USER:controlstock_iam}
    password: ${DB_PASSWORD:}
  security:
    oauth2:
      resourceserver:
        jwt:
          jwk-set-uri: ${KEYCLOAK_JWK_URI:http://localhost:8180/realms/controlstock/protocol/openid-connect/certs}
          issuer-uri: ${KEYCLOAK_ISSUER:http://localhost:8180/realms/controlstock}

keycloak:
  server-url: ${KEYCLOAK_URL:http://localhost:8180}
  realm: controlstock
  admin-client-id: ${KEYCLOAK_ADMIN_CLIENT_ID:admin-cli}
  admin-client-secret: ${KEYCLOAK_ADMIN_SECRET:}

management:
  endpoints:
    web:
      exposure:
        include: health,prometheus
  endpoint:
    health:
      probes:
        enabled: true
```

---

## API REST

### Tabla de endpoints

| Método | Path | Descripción | Body Request | Response |
|--------|------|-------------|-------------|---------|
| `POST` | `/iam/users` | Crear usuario en Keycloak y BD local | `CrearUsuarioRequest` | `201 UsuarioDTO` |
| `GET` | `/iam/users` | Listar todos los usuarios | — | `200 List<UsuarioDTO>` |
| `GET` | `/iam/users/{id}` | Obtener usuario por ID | — | `200 UsuarioDTO` |
| `PUT` | `/iam/users/{id}` | Actualizar datos del usuario | `ActualizarUsuarioRequest` | `200 UsuarioDTO` |
| `POST` | `/iam/users/{id}/inactivar` | Desactivar usuario | — | `204 No Content` |
| `GET` | `/iam/roles` | Listar roles | — | `200 List<RolDTO>` |
| `POST` | `/iam/roles` | Crear rol | `CrearRolRequest` | `201 RolDTO` |
| `POST` | `/iam/users/{id}/roles` | Asignar rol a usuario | `AsignarRolRequest` | `204 No Content` |
| `DELETE` | `/iam/users/{id}/roles/{roleId}` | Revocar rol de usuario | — | `204 No Content` |
| `GET` | `/iam/permissions` | Listar permisos | — | `200 List<PermisoDTO>` |

### Implementación con `@RestController` (WebFlux)

```java
@RestController
@RequestMapping("/iam")
@RequiredArgsConstructor
public class IamController {

    private final CrearUsuarioUseCase crearUsuarioUseCase;
    private final InactivarUsuarioUseCase inactivarUsuarioUseCase;
    private final AsignarRolUseCase asignarRolUseCase;
    private final RevocarRolUseCase revocarRolUseCase;
    private final ListarUsuariosUseCase listarUsuariosUseCase;
    private final CrearRolUseCase crearRolUseCase;
    private final ListarRolesUseCase listarRolesUseCase;
    private final ListarPermisosUseCase listarPermisosUseCase;

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UsuarioDTO> crearUsuario(@Valid @RequestBody CrearUsuarioRequest request) {
        return crearUsuarioUseCase.ejecutar(CrearUsuarioCommand.from(request));
    }

    @GetMapping("/users")
    public Flux<UsuarioDTO> listarUsuarios() {
        return listarUsuariosUseCase.ejecutar();
    }

    @GetMapping("/users/{id}")
    public Mono<UsuarioDTO> obtenerUsuario(@PathVariable UUID id) {
        return listarUsuariosUseCase.ejecutarPorId(new UsuarioId(id));
    }

    @PostMapping("/users/{id}/inactivar")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> inactivarUsuario(@PathVariable UUID id) {
        return inactivarUsuarioUseCase.ejecutar(new UsuarioId(id));
    }

    @PostMapping("/users/{id}/roles")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> asignarRol(
            @PathVariable UUID id,
            @Valid @RequestBody AsignarRolRequest request) {
        return asignarRolUseCase.ejecutar(new UsuarioId(id), new RolId(request.rolId()));
    }

    @DeleteMapping("/users/{id}/roles/{roleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> revocarRol(@PathVariable UUID id, @PathVariable UUID roleId) {
        return revocarRolUseCase.ejecutar(new UsuarioId(id), new RolId(roleId));
    }

    @GetMapping("/roles")
    public Flux<RolDTO> listarRoles() {
        return listarRolesUseCase.ejecutar();
    }

    @PostMapping("/roles")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<RolDTO> crearRol(@Valid @RequestBody CrearRolRequest request) {
        return crearRolUseCase.ejecutar(CrearRolCommand.from(request));
    }

    @GetMapping("/permissions")
    public Flux<PermisoDTO> listarPermisos() {
        return listarPermisosUseCase.ejecutar();
    }
}
```

### Manejo de errores (`@ExceptionHandler`)

```java
@RestControllerAdvice
public class IamExceptionHandler {

    @ExceptionHandler(UsuarioNoEncontradoException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleUsuarioNoEncontrado(UsuarioNoEncontradoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_NO_ENCONTRADO", ex.getMessage()));
    }

    @ExceptionHandler(EmailDuplicadoException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ErrorResponse> handleEmailDuplicado(EmailDuplicadoException ex) {
        return Mono.just(new ErrorResponse("EMAIL_DUPLICADO", ex.getMessage()));
    }

    @ExceptionHandler(UsuarioYaInactivoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleYaInactivo(UsuarioYaInactivoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_YA_INACTIVO", ex.getMessage()));
    }

    @ExceptionHandler(UsuarioInactivoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleInactivo(UsuarioInactivoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_INACTIVO", ex.getMessage()));
    }

    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleValidation(WebExchangeBindException ex) {
        String mensaje = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .collect(Collectors.joining(", "));
        return Mono.just(new ErrorResponse("VALIDACION_FALLIDA", mensaje));
    }
}
```

---

## Especificación TDD por Capa (Red-Green-Refactor)

### Umbrales de cobertura requeridos

| Capa | Cobertura mínima | Herramienta |
|------|-----------------|-------------|
| Dominio | ≥ 90% | JaCoCo |
| Aplicación | ≥ 85% | JaCoCo |
| Infraestructura | ≥ 80% | JaCoCo + Testcontainers |
| API REST | ≥ 80% | JaCoCo + @WebFluxTest |

### Capa de Dominio — Tests

Principio: tests **sin Spring context** (JUnit 5 + AssertJ). Los mocks se hacen con Mockito o implementaciones stub puras.

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `UsuarioTest` | `crearUsuario_conEmailValido_debeSetearEstadoActivo` | Estado inicial = ACTIVO | Implementación de `Usuario.crear()` |
| `UsuarioTest` | `inactivar_usuarioActivo_debeSetearEstadoInactivo` | `inactivar()` cambia estado a INACTIVO | Implementación de `inactivar()` |
| `UsuarioTest` | `inactivar_usuarioYaInactivo_debeLanzarExcepcion` | No se puede inactivar dos veces | Excepción `UsuarioYaInactivoException` |
| `UsuarioTest` | `asignarRol_usuarioActivo_debeAgregarRolALaColeccion` | Roles se acumulan en Set | Implementación de `asignarRol()` |
| `UsuarioTest` | `asignarRol_usuarioInactivo_debeLanzarExcepcion` | Usuario inactivo no puede tener roles | Excepción `UsuarioInactivoException` |
| `UsuarioTest` | `revocarRol_rolExistente_debeEliminarRolDeColeccion` | Revocación actualiza Set de roles | Implementación de `revocarRol()` |
| `UsuarioTest` | `revocarRol_rolNoAsignado_debeLanzarExcepcion` | No se puede revocar rol no asignado | Excepción `RolNoAsignadoException` |
| `EmailTest` | `email_conFormatoValido_debeNormalizarAMinusculas` | Email normalizado a lowercase | Implementación de `Email` VO |
| `EmailTest` | `email_conFormatoInvalido_debeLanzarExcepcion` | Formato RFC 5322 obligatorio | Excepción `EmailInvalidoException` |
| `EmailTest` | `email_superiorA200Chars_debeLanzarExcepcion` | Longitud máxima 200 | Excepción `EmailDemasiadoLargoException` |
| `KeycloakSubTest` | `keycloakSub_nulo_debeLanzarExcepcion` | KeycloakSub no nulo | Implementación de `KeycloakSub` VO |
| `KeycloakSubTest` | `keycloakSub_vacio_debeLanzarExcepcion` | KeycloakSub no vacío | Implementación de `KeycloakSub` VO |

### Capa de Aplicación — Tests

Principio: tests con **mocks de puertos** (Mockito + `StepVerifier` para tipos reactivos).

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `CrearUsuarioUseCaseTest` | `ejecutar_emailNuevo_debeCrearEnKeycloakYGuardarLocalmente` | Flujo feliz: Keycloak primero, BD después | Implementación de `CrearUsuarioUseCase` |
| `CrearUsuarioUseCaseTest` | `ejecutar_emailDuplicado_debeLanzarEmailDuplicadoException` | No duplicar emails | Excepción `EmailDuplicadoException` |
| `CrearUsuarioUseCaseTest` | `ejecutar_keycloakFalla_noDebePersistirEnBD` | Consistencia: si Keycloak falla, no guardar | Rollback lógico en use case |
| `InactivarUsuarioUseCaseTest` | `ejecutar_usuarioActivo_debeDesactivarEnKeycloakYBD` | Flujo feliz: ambos sistemas actualizados | Implementación de `InactivarUsuarioUseCase` |
| `InactivarUsuarioUseCaseTest` | `ejecutar_usuarioYaInactivo_debeLanzarExcepcion` | No inactivar dos veces | Propagación de excepción de dominio |
| `InactivarUsuarioUseCaseTest` | `ejecutar_usuarioNoExiste_debeLanzarUsuarioNoEncontradoException` | ID no encontrado | Excepción `UsuarioNoEncontradoException` |
| `AsignarRolUseCaseTest` | `ejecutar_usuarioActivoYRolExistente_debeAsignarEnKeycloakYBD` | Flujo feliz | Implementación de `AsignarRolUseCase` |
| `AsignarRolUseCaseTest` | `ejecutar_usuarioInactivo_debeLanzarExcepcion` | Usuario inactivo no recibe roles | Propagación de excepción de dominio |
| `AsignarRolUseCaseTest` | `ejecutar_rolNoExiste_debeLanzarRolNoEncontradoException` | Rol debe existir para asignarse | Excepción `RolNoEncontradoException` |
| `RevocarRolUseCaseTest` | `ejecutar_rolAsignado_debeRevocarEnKeycloakYBD` | Flujo feliz | Implementación de `RevocarRolUseCase` |
| `RevocarRolUseCaseTest` | `ejecutar_rolNoAsignado_debeLanzarExcepcion` | No revocar rol que no se tiene | Propagación de excepción de dominio |
| `ListarUsuariosUseCaseTest` | `ejecutar_debeRetornarFluxDeTodosLosUsuarios` | Listado completo | Implementación de `ListarUsuariosUseCase` |

### Capa de Infraestructura — Tests (Testcontainers)

Principio: tests de integración con **PostgreSQL real** en Testcontainers. Usar `@Testcontainers` + `@Container`.

```java
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(properties = {
    "spring.r2dbc.url=r2dbc:postgresql://${TC_POSTGRES_HOST}:${TC_POSTGRES_PORT}/test_iam"
})
class UsuarioR2dbcAdapterTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16")
        .withDatabaseName("test_iam")
        .withInitScript("db/migration/V1__init_iam.sql");

    @Autowired
    private UsuarioR2dbcAdapter adapter;

    @Test
    void save_usuarioNuevo_debeGuardarYRetornar() {
        Usuario usuario = crearUsuarioFake();
        StepVerifier.create(adapter.save(usuario))
            .assertNext(saved -> {
                assertThat(saved.getId()).isEqualTo(usuario.getId());
                assertThat(saved.getEmail()).isEqualTo(usuario.getEmail());
            })
            .verifyComplete();
    }
}
```

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `UsuarioR2dbcAdapterTest` | `save_usuarioNuevo_debeGuardarYRetornar` | INSERT funciona correctamente | Implementación del adaptador |
| `UsuarioR2dbcAdapterTest` | `save_usuarioExistente_debeActualizarPorUpsert` | ON CONFLICT UPDATE funciona | Lógica de upsert en SQL |
| `UsuarioR2dbcAdapterTest` | `findById_idExistente_debeRetornarUsuario` | SELECT por PK funciona | Implementación de `findById` |
| `UsuarioR2dbcAdapterTest` | `findById_idNoExistente_debeRetornarMonoError` | Not found lanza excepción | `switchIfEmpty` en adaptador |
| `UsuarioR2dbcAdapterTest` | `existsByEmail_emailExistente_debeRetornarTrue` | Detección de duplicados funciona | Implementación de `existsByEmail` |
| `UsuarioR2dbcAdapterTest` | `findByEmail_emailExistente_debeRetornarUsuario` | Búsqueda por email funciona | Implementación de `findByEmail` |
| `RolR2dbcAdapterTest` | `save_rolNuevo_debeGuardarYRetornar` | INSERT rol correcto | Implementación del adaptador rol |
| `RolR2dbcAdapterTest` | `findByNombre_nombreExistente_debeRetornarRol` | Búsqueda por nombre único | Implementación de `findByNombre` |
| `PermisoR2dbcAdapterTest` | `save_permisoNuevo_debeGuardarYRetornar` | INSERT permiso correcto | Implementación del adaptador permiso |
| `PermisoR2dbcAdapterTest` | `existsByModuloAndOperacion_duplicado_debeRetornarTrue` | Unicidad (modulo, operacion) | Verificación de constraint |
| `UsuarioRolesAdapterTest` | `save_relacionNueva_debeGuardar` | INSERT en tabla de relación | Implementación de `UsuarioRolesR2dbcAdapter` |
| `UsuarioRolesAdapterTest` | `save_relacionDuplicada_noDebeFallar` | ON CONFLICT DO NOTHING | Idempotencia de asignación |
| `UsuarioRolesAdapterTest` | `delete_relacionExistente_debeEliminar` | DELETE funciona | Implementación de `delete` |
| `KeycloakAdapterTest` | `crearUsuario_exitoso_debeRetornarKeycloakSub` | Keycloak crea usuario y retorna ID | Implementación con WireMock |
| `KeycloakAdapterTest` | `crearUsuario_emailDuplicado_debeLanzarExcepcion` | HTTP 409 de Keycloak mapeado | Manejo de errores Keycloak |
| `KeycloakAdapterTest` | `desactivarUsuario_exitoso_debeLlamarAPI` | PUT a Keycloak con enabled=false | Implementación de `desactivarUsuario` |

### Capa API REST — Tests (@WebFluxTest)

Principio: tests de controlador con **mocks de use cases** y `WebTestClient`. Spring Security desactivado en tests de unidad del controlador.

| Clase de Test | Método de Test | Invariante/Regla | Qué precede |
|--------------|---------------|-----------------|------------|
| `IamControllerTest` | `crearUsuario_requestValido_debeRetornar201` | Endpoint POST /iam/users funciona | Implementación del controlador |
| `IamControllerTest` | `crearUsuario_emailDuplicado_debeRetornar409` | Error 409 mapeado correctamente | `@ExceptionHandler` EmailDuplicado |
| `IamControllerTest` | `crearUsuario_requestInvalido_debeRetornar400` | Validación de @Valid funciona | `@ExceptionHandler` WebExchangeBindException |
| `IamControllerTest` | `listarUsuarios_debeRetornar200ConLista` | GET /iam/users retorna Flux | Implementación de `listarUsuarios` |
| `IamControllerTest` | `obtenerUsuario_idExistente_debeRetornar200` | GET /iam/users/{id} funciona | Implementación de `obtenerUsuario` |
| `IamControllerTest` | `obtenerUsuario_idNoExistente_debeRetornar404` | Error 404 mapeado correctamente | `@ExceptionHandler` UsuarioNoEncontrado |
| `IamControllerTest` | `inactivarUsuario_exitoso_debeRetornar204` | POST /iam/users/{id}/inactivar funciona | Implementación de `inactivarUsuario` |
| `IamControllerTest` | `inactivarUsuario_yaInactivo_debeRetornar422` | Error 422 mapeado correctamente | `@ExceptionHandler` UsuarioYaInactivo |
| `IamControllerTest` | `asignarRol_exitoso_debeRetornar204` | POST /iam/users/{id}/roles funciona | Implementación de `asignarRol` |
| `IamControllerTest` | `revocarRol_exitoso_debeRetornar204` | DELETE /iam/users/{id}/roles/{roleId} | Implementación de `revocarRol` |
| `IamControllerTest` | `listarRoles_debeRetornar200ConLista` | GET /iam/roles funciona | Implementación de `listarRoles` |
| `IamControllerTest` | `crearRol_requestValido_debeRetornar201` | POST /iam/roles funciona | Implementación de `crearRol` |
| `IamControllerTest` | `listarPermisos_debeRetornar200ConLista` | GET /iam/permissions funciona | Implementación de `listarPermisos` |
| `SecurityTest` | `endpoint_sinToken_debeRetornar401` | Protección JWT activa | Configuración Spring Security |
| `SecurityTest` | `endpoint_conTokenValido_debePermitirAcceso` | JWT RS256 validado correctamente | Integración con Keycloak JWKS |
| `SecurityTest` | `actuatorHealth_sinToken_debeRetornar200` | Actuator es público | Configuración de exclusión en Security |

---

## Criterios de Aceptación

### Dominio

| # | Criterio | Verificación |
|---|----------|-------------|
| 1 | Entidades `Usuario`, `Rol`, `Permiso` implementadas con invariantes | Tests dominio ≥ 90% cobertura |
| 2 | VOs `Email` y `KeycloakSub` validan y normalizan correctamente | Tests `EmailTest` y `KeycloakSubTest` GREEN |
| 3 | `usuario.inactivar()` lanza excepción si ya inactivo | Test `inactivar_usuarioYaInactivo` GREEN |
| 4 | `usuario.asignarRol()` lanza excepción si usuario inactivo | Test `asignarRol_usuarioInactivo` GREEN |
| 5 | `usuario.revocarRol()` lanza excepción si rol no asignado | Test `revocarRol_rolNoAsignado` GREEN |

### TDD por capa

| # | Criterio | Verificación |
|---|----------|-------------|
| 6 | Todos los tests de dominio escritos ANTES de la implementación (ciclo RED-GREEN-REFACTOR) | Historial de commits muestra test primero |
| 7 | Tests de aplicación usan mocks de puertos (sin Spring context) | No hay `@SpringBootTest` en tests de aplicación |
| 8 | Tests de infraestructura usan Testcontainers con PostgreSQL real | `@Testcontainers` + `PostgreSQLContainer` visible |
| 9 | Tests de API REST usan `WebTestClient` con mocks de use cases | `@WebFluxTest` visible en tests de controlador |
| 10 | Cobertura dominio ≥ 90% | Reporte JaCoCo en Jenkins |
| 11 | Cobertura aplicación ≥ 85% | Reporte JaCoCo en Jenkins |
| 12 | Cobertura infraestructura ≥ 80% | Reporte JaCoCo en Jenkins |
| 13 | Cobertura API REST ≥ 80% | Reporte JaCoCo en Jenkins |

### Infraestructura y base de datos

| # | Criterio | Verificación |
|---|----------|-------------|
| 14 | Adaptadores R2DBC implementados para las 5 tablas de BC-01 | Tests Testcontainers GREEN |
| 15 | `KeycloakAdapter` crea usuarios en Keycloak y retorna `keycloak_sub` | Test con WireMock GREEN |
| 16 | `KeycloakAdapter` desactiva usuarios en Keycloak correctamente | Test con WireMock GREEN |
| 17 | Spring Security valida JWT RS256 con JWKS de Keycloak | Test `SecurityTest` GREEN |
| 18 | Endpoints del Actuator (`/health/readiness`, `/prometheus`) son públicos | Test `SecurityTest` GREEN |

### API REST

| # | Criterio | Verificación |
|---|----------|-------------|
| 19 | Los 10 endpoints de la API están implementados y retornan códigos HTTP correctos | Tabla de endpoints cubierta al 100% |
| 20 | `POST /iam/users` retorna 409 si email ya existe | Test GREEN |
| 21 | `POST /iam/users/{id}/inactivar` retorna 422 si usuario ya inactivo | Test GREEN |
| 22 | Todos los endpoints protegidos retornan 401 sin token | Test `SecurityTest` GREEN |
| 23 | `@ExceptionHandler` centraliza manejo de errores en `ErrorResponse` JSON | Tests de error GREEN |

### Pipeline CI/CD y despliegue

| # | Criterio | Verificación |
|---|----------|-------------|
| 24 | Pipeline Jenkins completa todas las etapas para `iam-service` | BlueOcean muestra todas las etapas en verde |
| 25 | Imagen `iam-service:<tag>` publicada en Gitea registry | `docker pull <VPS_IP>:3000/controlstock/iam-service:<tag>` exitoso |
| 26 | ArgoCD despliega la imagen en namespace `apps` | `kubectl get pod -n apps -l app=iam-service` Running |
| 27 | `GET /actuator/health/readiness` retorna 200 en K3s | Smoke test del pipeline GREEN |
| 28 | `GET /actuator/prometheus` retorna métricas | Stage `Smoke Tests` GREEN |
| 29 | SonarQube Quality Gate pasa para `iam-service` | Stage `Quality Gates` verde en Jenkins |
