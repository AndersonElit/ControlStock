package com.iamservice.usecases;

import java.time.Instant;
import java.util.UUID;

public record RolDTO(UUID id, String nombre, String descripcion, Instant createdAt) {}
