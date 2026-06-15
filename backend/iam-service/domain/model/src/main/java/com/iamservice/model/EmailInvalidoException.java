package com.iamservice.model;

public class EmailInvalidoException extends RuntimeException {
    public EmailInvalidoException(String email) {
        super("El email '" + email + "' no tiene un formato válido");
    }
}
