package com.iamservice.model;

import com.iamservice.model.vo.KeycloakSub;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class KeycloakSubTest {

    @Test
    void keycloakSub_valido_debeCrearseCorrectamente() {
        KeycloakSub sub = new KeycloakSub("abc-123-def");
        assertThat(sub.value()).isEqualTo("abc-123-def");
    }

    @Test
    void keycloakSub_nulo_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new KeycloakSub(null))
                .isInstanceOf(NullPointerException.class);
    }

    @Test
    void keycloakSub_vacio_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new KeycloakSub(""))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void keycloakSub_soloEspacios_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new KeycloakSub("   "))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void equals_mismoValor_debeSerIgual() {
        KeycloakSub a = new KeycloakSub("abc");
        KeycloakSub b = new KeycloakSub("abc");
        assertThat(a).isEqualTo(b);
        assertThat(a.hashCode()).isEqualTo(b.hashCode());
    }
}
