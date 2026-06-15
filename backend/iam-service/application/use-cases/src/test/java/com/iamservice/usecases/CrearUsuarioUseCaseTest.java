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
class CrearUsuarioUseCaseTest {

    @Mock private UsuarioRepository usuarioRepository;
    @Mock private KeycloakGateway keycloakGateway;
    private CrearUsuarioUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new CrearUsuarioUseCase(usuarioRepository, keycloakGateway);
    }

    @Test
    void ejecutar_emailNuevo_debeCrearEnKeycloakYGuardarLocalmente() {
        when(usuarioRepository.existsByEmail(any())).thenReturn(Mono.just(false));
        when(keycloakGateway.crearUsuario(any(), any(), any()))
                .thenReturn(Mono.just(new KeycloakSub("sub-123")));
        when(usuarioRepository.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        StepVerifier.create(useCase.ejecutar(
                new CrearUsuarioCommand("test@controlstock.com", "Juan", "pass123")))
                .expectNextMatches(dto ->
                        dto.email().equals("test@controlstock.com") &&
                        dto.nombre().equals("Juan") &&
                        dto.estado().equals("ACTIVO"))
                .verifyComplete();

        verify(keycloakGateway).crearUsuario("test@controlstock.com", "Juan", "pass123");
        verify(usuarioRepository).save(any());
    }

    @Test
    void ejecutar_emailDuplicado_debeLanzarEmailDuplicadoException() {
        when(usuarioRepository.existsByEmail(any())).thenReturn(Mono.just(true));

        StepVerifier.create(useCase.ejecutar(
                new CrearUsuarioCommand("dup@controlstock.com", "Ana", "pass")))
                .expectError(EmailDuplicadoException.class)
                .verify();

        verify(keycloakGateway, never()).crearUsuario(any(), any(), any());
        verify(usuarioRepository, never()).save(any());
    }

    @Test
    void ejecutar_keycloakFalla_noDebePersistirEnBD() {
        when(usuarioRepository.existsByEmail(any())).thenReturn(Mono.just(false));
        when(keycloakGateway.crearUsuario(any(), any(), any()))
                .thenReturn(Mono.error(new RuntimeException("Keycloak error")));

        StepVerifier.create(useCase.ejecutar(
                new CrearUsuarioCommand("fail@test.com", "Pedro", "pass")))
                .expectError(RuntimeException.class)
                .verify();

        verify(usuarioRepository, never()).save(any());
    }
}
