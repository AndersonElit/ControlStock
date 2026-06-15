package com.iamservice.usecases;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record UsuarioDTO(
        UUID id,
        String keycloakSub,
        String email,
        String nombre,
        String estado,
        Instant createdAt,
        Instant updatedAt,
        List<RolResumenDTO> roles
) {}
