package com.iamservice.model;

import com.iamservice.model.vo.UsuarioId;
import org.junit.jupiter.api.Test;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class UsuarioIdTest {

    @Test
    void usuarioId_conUUID_debeCrearseCorrectamente() {
        UUID uuid = UUID.randomUUID();
        UsuarioId id = new UsuarioId(uuid);
        assertThat(id.value()).isEqualTo(uuid);
    }

    @Test
    void usuarioId_nulo_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new UsuarioId(null))
                .isInstanceOf(NullPointerException.class);
    }

    @Test
    void generate_debeCrearUUIDValido() {
        UsuarioId id = UsuarioId.generate();
        assertThat(id.value()).isNotNull();
    }
}
