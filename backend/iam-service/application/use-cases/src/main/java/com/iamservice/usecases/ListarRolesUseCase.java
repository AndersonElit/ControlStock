package com.iamservice.usecases;

import com.iamservice.model.RolRepository;
import reactor.core.publisher.Flux;

public class ListarRolesUseCase {
    private final RolRepository rolRepository;

    public ListarRolesUseCase(RolRepository rolRepository) {
        this.rolRepository = rolRepository;
    }

    public Flux<RolDTO> ejecutar() {
        return rolRepository.findAll().map(r -> new RolDTO(
                r.getId().value(), r.getNombre(), r.getDescripcion(), r.getCreatedAt()
        ));
    }
}
