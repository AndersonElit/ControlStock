package com.iamservice.model;

import com.iamservice.model.vo.RolId;

public class RolNoEncontradoException extends RuntimeException {
    public RolNoEncontradoException(RolId id) {
        super("Rol no encontrado: " + id.value());
    }
}
