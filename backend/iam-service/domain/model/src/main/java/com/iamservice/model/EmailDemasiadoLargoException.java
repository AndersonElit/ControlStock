package com.iamservice.model;

public class EmailDemasiadoLargoException extends RuntimeException {
    public EmailDemasiadoLargoException(String email) {
        super("El email excede los 200 caracteres permitidos");
    }
}
