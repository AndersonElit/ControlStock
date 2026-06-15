package com.iamservice.usecases;

import java.util.UUID;

public record AsignarRolCommand(UUID usuarioId, UUID rolId) {
    public AsignarRolCommand {
        if (usuarioId == null) throw new IllegalArgumentException("usuarioId requerido");
        if (rolId == null) throw new IllegalArgumentException("rolId requerido");
    }
}
