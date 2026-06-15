package com.iamservice.model;

public class EmailDuplicadoException extends RuntimeException {
    public EmailDuplicadoException(String email) {
        super("El email '" + email + "' ya está registrado en el sistema");
    }
}
