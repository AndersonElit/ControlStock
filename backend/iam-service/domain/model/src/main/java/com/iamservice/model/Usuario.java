package com.iamservice.model;

import com.iamservice.model.vo.*;
import java.time.Instant;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

public class Usuario {
    private final UsuarioId id;
    private final KeycloakSub keycloakSub;
    private final Email email;
    private String nombre;
    private EstadoUsuario estado;
    private final Instant createdAt;
    private Instant updatedAt;
    private final Set<RolId> roles;

    private Usuario(UsuarioId id, KeycloakSub keycloakSub, Email email,
                    String nombre, EstadoUsuario estado,
                    Instant createdAt, Instant updatedAt) {
        this.id = id;
        this.keycloakSub = keycloakSub;
        this.email = email;
        this.nombre = nombre;
        this.estado = estado;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.roles = new HashSet<>();
    }

    public static Usuario crear(KeycloakSub sub, Email email, String nombre) {
        return new Usuario(
                UsuarioId.generate(),
                sub,
                email,
                nombre,
                EstadoUsuario.ACTIVO,
                Instant.now(),
                Instant.now()
        );
    }

    public static Usuario reconstituir(UsuarioId id, KeycloakSub keycloakSub,
                                       Email email, String nombre,
                                       EstadoUsuario estado,
                                       Instant createdAt, Instant updatedAt) {
        return new Usuario(id, keycloakSub, email, nombre, estado, createdAt, updatedAt);
    }

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

    public UsuarioId getId() { return id; }
    public KeycloakSub getKeycloakSub() { return keycloakSub; }
    public Email getEmail() { return email; }
    public String getNombre() { return nombre; }
    public EstadoUsuario getEstado() { return estado; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Set<RolId> getRoles() { return Collections.unmodifiableSet(roles); }
}
