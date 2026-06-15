package com.iamservice.usecases;

import com.iamservice.model.*;
import com.iamservice.model.vo.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AsignarRolUseCaseTest {

    @Mock private UsuarioRepository usuarioRepository;
    @Mock private RolRepository rolRepository;
    @Mock private KeycloakGateway keycloakGateway;
    private AsignarRolUseCase useCase;
    private UsuarioId usuarioId;
    private RolId rolId;
    private Usuario usuario;
    private Rol rol;

    @BeforeEach
    void setUp() {
        useCase = new AsignarRolUseCase(usuarioRepository, rolRepository, keycloakGateway);
        usuarioId = UsuarioId.generate();
        rolId = RolId.generate();
        usuario = Usuario.crear(new KeycloakSub("sub-1"), new Email("a@test.com"), "Test");
        rol = Rol.crear("ADMIN", "Administrador");
    }

    @Test
    void ejecutar_usuarioActivoYRolExistente_debeAsignarEnKeycloakYBD() {
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.just(usuario));
        when(rolRepository.findById(rolId)).thenReturn(Mono.just(rol));
        when(keycloakGateway.asignarRol(any(), any())).thenReturn(Mono.empty());
        when(usuarioRepository.save(any())).thenReturn(Mono.just(usuario));

        StepVerifier.create(useCase.ejecutar(usuarioId, rolId))
                .verifyComplete();

        verify(keycloakGateway).asignarRol(usuario.getKeycloakSub(), "ADMIN");
        verify(usuarioRepository).save(any());
    }

    @Test
    void ejecutar_usuarioInactivo_debeLanzarExcepcion() {
        usuario.inactivar();
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.just(usuario));
        when(rolRepository.findById(rolId)).thenReturn(Mono.just(rol));

        StepVerifier.create(useCase.ejecutar(usuarioId, rolId))
                .expectError(UsuarioInactivoException.class)
                .verify();

        verify(keycloakGateway, never()).asignarRol(any(), any());
    }

    @Test
    void ejecutar_rolNoExiste_debeLanzarRolNoEncontradoException() {
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.just(usuario));
        when(rolRepository.findById(rolId)).thenReturn(Mono.empty());

        StepVerifier.create(useCase.ejecutar(usuarioId, rolId))
                .expectError(RolNoEncontradoException.class)
                .verify();

        verify(keycloakGateway, never()).asignarRol(any(), any());
    }
}
