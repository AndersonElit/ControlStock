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
class InactivarUsuarioUseCaseTest {

    @Mock private UsuarioRepository usuarioRepository;
    @Mock private KeycloakGateway keycloakGateway;
    private InactivarUsuarioUseCase useCase;
    private UsuarioId usuarioId;
    private Usuario usuario;

    @BeforeEach
    void setUp() {
        useCase = new InactivarUsuarioUseCase(usuarioRepository, keycloakGateway);
        usuarioId = UsuarioId.generate();
        usuario = Usuario.crear(new KeycloakSub("sub-1"), new Email("a@test.com"), "Test");
    }

    @Test
    void ejecutar_usuarioActivo_debeDesactivarEnKeycloakYBD() {
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.just(usuario));
        when(keycloakGateway.desactivarUsuario(any())).thenReturn(Mono.empty());
        when(usuarioRepository.save(any())).thenReturn(Mono.just(usuario));

        StepVerifier.create(useCase.ejecutar(usuarioId))
                .verifyComplete();

        verify(keycloakGateway).desactivarUsuario(usuario.getKeycloakSub());
        verify(usuarioRepository).save(any());
    }

    @Test
    void ejecutar_usuarioYaInactivo_debeLanzarExcepcion() {
        usuario.inactivar();
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.just(usuario));

        StepVerifier.create(useCase.ejecutar(usuarioId))
                .expectError(UsuarioYaInactivoException.class)
                .verify();

        verify(keycloakGateway, never()).desactivarUsuario(any());
    }

    @Test
    void ejecutar_usuarioNoExiste_debeLanzarUsuarioNoEncontradoException() {
        when(usuarioRepository.findById(usuarioId)).thenReturn(Mono.empty());

        StepVerifier.create(useCase.ejecutar(usuarioId))
                .expectError(UsuarioNoEncontradoException.class)
                .verify();
    }
}
