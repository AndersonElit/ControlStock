package com.iamservice.model.vo;

import java.util.Objects;
import java.util.UUID;

public record UsuarioId(UUID value) {
    public UsuarioId {
        Objects.requireNonNull(value, "usuarioId no puede ser nulo");
    }

    public static UsuarioId generate() {
        return new UsuarioId(UUID.randomUUID());
    }
}
