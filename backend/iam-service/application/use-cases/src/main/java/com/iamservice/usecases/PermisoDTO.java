package com.iamservice.usecases;

import java.util.UUID;

public record PermisoDTO(UUID id, String modulo, String operacion, String descripcion) {}
