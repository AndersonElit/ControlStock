package com.iamservice.usecases;

import com.iamservice.model.Rol;
import com.iamservice.model.RolRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public class CrearRolUseCase {
    private final RolRepository rolRepository;

    public CrearRolUseCase(RolRepository rolRepository) {
        this.rolRepository = rolRepository;
    }

    public Mono<RolDTO> ejecutar(CrearRolCommand command) {
        Rol rol = Rol.crear(command.nombre(), command.descripcion());
        return rolRepository.save(rol).map(r -> new RolDTO(
                r.getId().value(), r.getNombre(), r.getDescripcion(), r.getCreatedAt()
        ));
    }
}
