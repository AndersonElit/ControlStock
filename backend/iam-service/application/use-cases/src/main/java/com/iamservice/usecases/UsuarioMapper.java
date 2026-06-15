package com.iamservice.usecases;

import com.iamservice.model.Usuario;
import java.util.Collections;

public class UsuarioMapper {
    public static UsuarioDTO toDTO(Usuario usuario) {
        return new UsuarioDTO(
                usuario.getId().value(),
                usuario.getKeycloakSub().value(),
                usuario.getEmail().value(),
                usuario.getNombre(),
                usuario.getEstado().name(),
                usuario.getCreatedAt(),
                usuario.getUpdatedAt(),
                Collections.emptyList()
        );
    }

    public static UsuarioDTO toDTOWithRoles(Usuario usuario, java.util.List<RolResumenDTO> roles) {
        return new UsuarioDTO(
                usuario.getId().value(),
                usuario.getKeycloakSub().value(),
                usuario.getEmail().value(),
                usuario.getNombre(),
                usuario.getEstado().name(),
                usuario.getCreatedAt(),
                usuario.getUpdatedAt(),
                roles
        );
    }
}
