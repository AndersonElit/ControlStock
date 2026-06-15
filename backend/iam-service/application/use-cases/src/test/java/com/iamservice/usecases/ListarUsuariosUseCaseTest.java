package com.iamservice.usecases;

import com.iamservice.model.*;
import com.iamservice.model.vo.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ListarUsuariosUseCaseTest {

    @Mock private UsuarioRepository usuarioRepository;
    private ListarUsuariosUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new ListarUsuariosUseCase(usuarioRepository);
    }

    @Test
    void ejecutar_debeRetornarFluxDeTodosLosUsuarios() {
        Usuario u1 = Usuario.crear(new KeycloakSub("sub-1"), new Email("a@test.com"), "A");
        Usuario u2 = Usuario.crear(new KeycloakSub("sub-2"), new Email("b@test.com"), "B");
        when(usuarioRepository.findAll()).thenReturn(Flux.just(u1, u2));

        StepVerifier.create(useCase.ejecutar())
                .expectNextCount(2)
                .verifyComplete();
    }
}
