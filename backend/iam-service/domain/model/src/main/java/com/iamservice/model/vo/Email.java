package com.iamservice.model.vo;

import com.iamservice.model.EmailDemasiadoLargoException;
import com.iamservice.model.EmailInvalidoException;

import java.util.Objects;

public record Email(String value) {
    public Email {
        Objects.requireNonNull(value, "email no puede ser nulo");
        String normalized = value.strip().toLowerCase();
        if (normalized.isEmpty() || !normalized.matches("^[^@]+@[^@]+\\.[^@]+$")) {
            throw new EmailInvalidoException(value);
        }
        if (normalized.length() > 200) {
            throw new EmailDemasiadoLargoException(value);
        }
        value = normalized;
    }
}
