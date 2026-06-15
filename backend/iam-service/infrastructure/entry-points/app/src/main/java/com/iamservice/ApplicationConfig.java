package com.iamservice;

import com.iamservice.keycloak.KeycloakAdapter;
import com.iamservice.model.*;
import com.iamservice.usecases.*;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;

@Configuration
@ComponentScan(basePackages = {
        "com.iamservice.restapi",
        "com.iamservice.postgres",
        "com.iamservice.keycloak"
})
public class ApplicationConfig {

    @Bean
    public CrearUsuarioUseCase crearUsuarioUseCase(UsuarioRepository usuarioRepository,
                                                    KeycloakGateway keycloakGateway) {
        return new CrearUsuarioUseCase(usuarioRepository, keycloakGateway);
    }

    @Bean
    public InactivarUsuarioUseCase inactivarUsuarioUseCase(UsuarioRepository usuarioRepository,
                                                            KeycloakGateway keycloakGateway) {
        return new InactivarUsuarioUseCase(usuarioRepository, keycloakGateway);
    }

    @Bean
    public AsignarRolUseCase asignarRolUseCase(UsuarioRepository usuarioRepository,
                                                RolRepository rolRepository,
                                                KeycloakGateway keycloakGateway) {
        return new AsignarRolUseCase(usuarioRepository, rolRepository, keycloakGateway);
    }

    @Bean
    public RevocarRolUseCase revocarRolUseCase(UsuarioRepository usuarioRepository,
                                                RolRepository rolRepository,
                                                KeycloakGateway keycloakGateway) {
        return new RevocarRolUseCase(usuarioRepository, rolRepository, keycloakGateway);
    }

    @Bean
    public ListarUsuariosUseCase listarUsuariosUseCase(UsuarioRepository usuarioRepository) {
        return new ListarUsuariosUseCase(usuarioRepository);
    }

    @Bean
    public CrearRolUseCase crearRolUseCase(RolRepository rolRepository) {
        return new CrearRolUseCase(rolRepository);
    }

    @Bean
    public ListarRolesUseCase listarRolesUseCase(RolRepository rolRepository) {
        return new ListarRolesUseCase(rolRepository);
    }

    @Bean
    public ListarPermisosUseCase listarPermisosUseCase(PermisoRepository permisoRepository) {
        return new ListarPermisosUseCase(permisoRepository);
    }
}
