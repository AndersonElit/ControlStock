package com.iamservice.model;

import com.iamservice.model.vo.Email;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class EmailTest {

    @Test
    void email_conFormatoValido_debeNormalizarAMinusculas() {
        Email email = new Email("Usuario@Dominio.Com");
        assertThat(email.value()).isEqualTo("usuario@dominio.com");
    }

    @Test
    void email_conFormatoInvalido_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new Email("no-es-email"))
                .isInstanceOf(EmailInvalidoException.class);
        assertThatThrownBy(() -> new Email("sinArroba.com"))
                .isInstanceOf(EmailInvalidoException.class);
        assertThatThrownBy(() -> new Email(""))
                .isInstanceOf(EmailInvalidoException.class);
    }

    @Test
    void email_nulo_debeLanzarExcepcion() {
        assertThatThrownBy(() -> new Email(null))
                .isInstanceOf(NullPointerException.class);
    }

    @Test
    void email_superiorA200Chars_debeLanzarExcepcion() {
        String largo = "a".repeat(195) + "@b.com";
        assertThatThrownBy(() -> new Email(largo))
                .isInstanceOf(EmailDemasiadoLargoException.class);
    }

    @Test
    void email_conEspacios_debeTrimmear() {
        Email email = new Email("  usuario@dominio.com  ");
        assertThat(email.value()).isEqualTo("usuario@dominio.com");
    }
}
