package com.iamservice.model;

import com.iamservice.model.vo.PermisoId;
import com.iamservice.model.vo.RolId;
import java.time.Instant;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

public class Rol {
    private final RolId id;
    private final String nombre;
    private final String descripcion;
    private final Instant createdAt;
    private Set<PermisoId> permisos;

    public Rol(RolId id, String nombre, String descripcion, Instant createdAt) {
        this.id = id;
        this.nombre = nombre;
        this.descripcion = descripcion;
        this.createdAt = createdAt;
        this.permisos = new HashSet<>();
    }

    public static Rol crear(String nombre, String descripcion) {
        return new Rol(RolId.generate(), nombre, descripcion, Instant.now());
    }

    public RolId getId() { return id; }
    public String getNombre() { return nombre; }
    public String getDescripcion() { return descripcion; }
    public Instant getCreatedAt() { return createdAt; }
    public Set<PermisoId> getPermisos() { return Collections.unmodifiableSet(permisos); }
}
