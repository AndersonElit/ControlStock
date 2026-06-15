package com.iamservice.usecases;

import com.iamservice.model.PermisoRepository;
import reactor.core.publisher.Flux;

public class ListarPermisosUseCase {
    private final PermisoRepository permisoRepository;

    public ListarPermisosUseCase(PermisoRepository permisoRepository) {
        this.permisoRepository = permisoRepository;
    }

    public Flux<PermisoDTO> ejecutar() {
        return permisoRepository.findAll().map(p -> new PermisoDTO(
                p.getId().value(), p.getModulo(), p.getOperacion(), p.getDescripcion()
        ));
    }
}
