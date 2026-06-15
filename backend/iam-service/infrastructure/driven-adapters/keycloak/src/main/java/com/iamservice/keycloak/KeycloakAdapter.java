package com.iamservice.keycloak;

import com.iamservice.model.KeycloakGateway;
import com.iamservice.model.vo.KeycloakSub;
import org.keycloak.admin.client.Keycloak;
import org.keycloak.representations.idm.CredentialRepresentation;
import org.keycloak.representations.idm.RoleRepresentation;
import org.keycloak.representations.idm.UserRepresentation;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import jakarta.ws.rs.core.Response;
import java.util.List;

@Component
public class KeycloakAdapter implements KeycloakGateway {

    private final Keycloak keycloakAdminClient;
    private final String realm;

    public KeycloakAdapter(
            @Value("${keycloak.server-url}") String serverUrl,
            @Value("${keycloak.realm}") String realm,
            @Value("${keycloak.admin-client-id}") String clientId,
            @Value("${keycloak.admin-client-secret}") String clientSecret) {
        this.realm = realm;
        this.keycloakAdminClient = Keycloak.getInstance(serverUrl, realm, clientId, clientSecret);
    }

    @Override
    public Mono<KeycloakSub> crearUsuario(String email, String nombre, String password) {
        return Mono.fromCallable(() -> {
            UserRepresentation user = new UserRepresentation();
            user.setEmail(email);
            user.setFirstName(nombre);
            user.setEnabled(true);
            user.setEmailVerified(false);
            user.setUsername(email);

            CredentialRepresentation cred = new CredentialRepresentation();
            cred.setType(CredentialRepresentation.PASSWORD);
            cred.setValue(password);
            cred.setTemporary(true);
            user.setCredentials(List.of(cred));

            try (Response response = keycloakAdminClient.realm(realm).users().create(user)) {
                if (response.getStatus() == 409) {
                    throw new RuntimeException("Email ya existe en Keycloak: " + email);
                }
                if (response.getStatus() != 201) {
                    throw new RuntimeException("Error Keycloak al crear usuario: " + response.getStatus());
                }
                String location = response.getHeaderString("Location");
                String userId = location.substring(location.lastIndexOf('/') + 1);
                return new KeycloakSub(userId);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }

    @Override
    public Mono<Void> actualizarUsuario(KeycloakSub sub, String nombre) {
        return Mono.fromRunnable(() -> {
            UserRepresentation user = keycloakAdminClient.realm(realm)
                    .users().get(sub.value()).toRepresentation();
            user.setFirstName(nombre);
            keycloakAdminClient.realm(realm).users().get(sub.value()).update(user);
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }

    @Override
    public Mono<Void> desactivarUsuario(KeycloakSub sub) {
        return Mono.fromRunnable(() -> {
            UserRepresentation user = keycloakAdminClient.realm(realm)
                    .users().get(sub.value()).toRepresentation();
            user.setEnabled(false);
            keycloakAdminClient.realm(realm).users().get(sub.value()).update(user);
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }

    @Override
    public Mono<Void> asignarRol(KeycloakSub sub, String rolNombre) {
        return Mono.fromRunnable(() -> {
            RoleRepresentation role = keycloakAdminClient.realm(realm)
                    .roles().get(rolNombre).toRepresentation();
            keycloakAdminClient.realm(realm).users().get(sub.value())
                    .roles().realmLevel().add(List.of(role));
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }

    @Override
    public Mono<Void> revocarRol(KeycloakSub sub, String rolNombre) {
        return Mono.fromRunnable(() -> {
            RoleRepresentation role = keycloakAdminClient.realm(realm)
                    .roles().get(rolNombre).toRepresentation();
            keycloakAdminClient.realm(realm).users().get(sub.value())
                    .roles().realmLevel().remove(List.of(role));
        }).subscribeOn(Schedulers.boundedElastic()).then();
    }
}
