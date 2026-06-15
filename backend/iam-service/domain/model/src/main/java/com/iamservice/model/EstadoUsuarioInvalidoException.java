package com.iamservice.model;

public class EstadoUsuarioInvalidoException extends RuntimeException {
    public EstadoUsuarioInvalidoException(String value) {
        super("Valor de estado inválido: '" + value + "'. Valores permitidos: ACTIVO, INACTIVO");
    }
}
