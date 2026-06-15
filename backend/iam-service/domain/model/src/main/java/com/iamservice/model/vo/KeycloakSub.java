package com.iamservice.model.vo;

import java.util.Objects;

public record KeycloakSub(String value) {
    public KeycloakSub {
        Objects.requireNonNull(value, "keycloakSub no puede ser nulo");
        if (value.isBlank()) {
            throw new IllegalArgumentException("keycloakSub no puede estar vacío");
        }
    }
}
