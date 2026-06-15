package com.iamservice.model.vo;

import java.util.Objects;
import java.util.UUID;

public record PermisoId(UUID value) {
    public PermisoId {
        Objects.requireNonNull(value, "permisoId no puede ser nulo");
    }

    public static PermisoId generate() {
        return new PermisoId(UUID.randomUUID());
    }
}
