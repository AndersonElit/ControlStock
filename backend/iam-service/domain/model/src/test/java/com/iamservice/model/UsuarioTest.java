package com.iamservice.model;

import com.iamservice.model.vo.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.time.Instant;
import static org.assertj.core.api.Assertions.*;

class UsuarioTest {

    private Usuario usuario;
    private RolId rolId;

    @BeforeEach
    void setUp() {
        usuario = Usuario.crear(
                new KeycloakSub("sub-123"),
                new Email("test@controlstock.com"),
                "Juan Perez"
        );
        rolId = RolId.generate();
    }

    @Test
    void crearUsuario_conDatosValidos_debeSetearEstadoActivo() {
        assertThat(usuario.getEstado()).isEqualTo(EstadoUsuario.ACTIVO);
        assertThat(usuario.getNombre()).isEqualTo("Juan Perez");
        assertThat(usuario.getEmail().value()).isEqualTo("test@controlstock.com");
        assertThat(usuario.getKeycloakSub().value()).isEqualTo("sub-123");
        assertThat(usuario.getId()).isNotNull();
        assertThat(usuario.getCreatedAt()).isNotNull();
        assertThat(usuario.getRoles()).isEmpty();
    }

    @Test
    void inactivar_usuarioActivo_debeSetearEstadoInactivo() {
        usuario.inactivar();
        assertThat(usuario.getEstado()).isEqualTo(EstadoUsuario.INACTIVO);
    }

    @Test
    void inactivar_usuarioYaInactivo_debeLanzarExcepcion() {
        usuario.inactivar();
        assertThatThrownBy(() -> usuario.inactivar())
                .isInstanceOf(UsuarioYaInactivoException.class);
    }

    @Test
    void asignarRol_usuarioActivo_debeAgregarRolALaColeccion() {
        usuario.asignarRol(rolId);
        assertThat(usuario.getRoles()).contains(rolId);
    }

    @Test
    void asignarRol_usuarioInactivo_debeLanzarExcepcion() {
        usuario.inactivar();
        assertThatThrownBy(() -> usuario.asignarRol(rolId))
                .isInstanceOf(UsuarioInactivoException.class);
    }

    @Test
    void revocarRol_rolExistente_debeEliminarRolDeColeccion() {
        usuario.asignarRol(rolId);
        usuario.revocarRol(rolId);
        assertThat(usuario.getRoles()).doesNotContain(rolId);
    }

    @Test
    void revocarRol_rolNoAsignado_debeLanzarExcepcion() {
        assertThatThrownBy(() -> usuario.revocarRol(rolId))
                .isInstanceOf(RolNoAsignadoException.class);
    }

    @Test
    void reconstituir_debeCrearUsuarioConTodosLosCampos() {
        UsuarioId id = UsuarioId.generate();
        Instant now = Instant.now();
        Usuario u = Usuario.reconstituir(
                id,
                new KeycloakSub("sub-456"),
                new Email("reconstituido@test.com"),
                "Ana",
                EstadoUsuario.ACTIVO,
                now,
                now
        );
        assertThat(u.getId()).isEqualTo(id);
        assertThat(u.getKeycloakSub().value()).isEqualTo("sub-456");
        assertThat(u.getEmail().value()).isEqualTo("reconstituido@test.com");
        assertThat(u.getNombre()).isEqualTo("Ana");
        assertThat(u.getEstado()).isEqualTo(EstadoUsuario.ACTIVO);
        assertThat(u.getCreatedAt()).isEqualTo(now);
        assertThat(u.getUpdatedAt()).isEqualTo(now);
    }
}
