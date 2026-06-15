package com.iamservice.model.vo;

import java.util.Objects;
import java.util.UUID;

public record RolId(UUID value) {
    public RolId {
        Objects.requireNonNull(value, "rolId no puede ser nulo");
    }

    public static RolId generate() {
        return new RolId(UUID.randomUUID());
    }
}
