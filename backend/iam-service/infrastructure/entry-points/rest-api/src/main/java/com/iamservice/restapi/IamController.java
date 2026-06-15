package com.iamservice.restapi;

import com.iamservice.model.vo.RolId;
import com.iamservice.model.vo.UsuarioId;
import com.iamservice.usecases.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.UUID;

@RestController
@RequestMapping("/iam")
public class IamController {

    private final CrearUsuarioUseCase crearUsuarioUseCase;
    private final InactivarUsuarioUseCase inactivarUsuarioUseCase;
    private final AsignarRolUseCase asignarRolUseCase;
    private final RevocarRolUseCase revocarRolUseCase;
    private final ListarUsuariosUseCase listarUsuariosUseCase;
    private final CrearRolUseCase crearRolUseCase;
    private final ListarRolesUseCase listarRolesUseCase;
    private final ListarPermisosUseCase listarPermisosUseCase;

    public IamController(CrearUsuarioUseCase crearUsuarioUseCase,
                         InactivarUsuarioUseCase inactivarUsuarioUseCase,
                         AsignarRolUseCase asignarRolUseCase,
                         RevocarRolUseCase revocarRolUseCase,
                         ListarUsuariosUseCase listarUsuariosUseCase,
                         CrearRolUseCase crearRolUseCase,
                         ListarRolesUseCase listarRolesUseCase,
                         ListarPermisosUseCase listarPermisosUseCase) {
        this.crearUsuarioUseCase = crearUsuarioUseCase;
        this.inactivarUsuarioUseCase = inactivarUsuarioUseCase;
        this.asignarRolUseCase = asignarRolUseCase;
        this.revocarRolUseCase = revocarRolUseCase;
        this.listarUsuariosUseCase = listarUsuariosUseCase;
        this.crearRolUseCase = crearRolUseCase;
        this.listarRolesUseCase = listarRolesUseCase;
        this.listarPermisosUseCase = listarPermisosUseCase;
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UsuarioDTO> crearUsuario(@Valid @RequestBody CrearUsuarioRequest request) {
        return crearUsuarioUseCase.ejecutar(
                new CrearUsuarioCommand(request.email(), request.nombre(), request.passwordTemporal()));
    }

    @GetMapping("/users")
    public Flux<UsuarioDTO> listarUsuarios() {
        return listarUsuariosUseCase.ejecutar();
    }

    @GetMapping("/users/{id}")
    public Mono<UsuarioDTO> obtenerUsuario(@PathVariable UUID id) {
        return listarUsuariosUseCase.ejecutar()
                .filter(u -> u.id().equals(id))
                .single();
    }

    @PostMapping("/users/{id}/inactivar")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> inactivarUsuario(@PathVariable UUID id) {
        return inactivarUsuarioUseCase.ejecutar(new UsuarioId(id));
    }

    @PostMapping("/users/{id}/roles")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> asignarRol(@PathVariable UUID id,
                                 @Valid @RequestBody AsignarRolRequest request) {
        return asignarRolUseCase.ejecutar(new UsuarioId(id), new RolId(request.rolId()));
    }

    @DeleteMapping("/users/{id}/roles/{roleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> revocarRol(@PathVariable UUID id, @PathVariable UUID roleId) {
        return revocarRolUseCase.ejecutar(new UsuarioId(id), new RolId(roleId));
    }

    @GetMapping("/roles")
    public Flux<RolDTO> listarRoles() {
        return listarRolesUseCase.ejecutar();
    }

    @PostMapping("/roles")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<RolDTO> crearRol(@Valid @RequestBody CrearRolRequest request) {
        return crearRolUseCase.ejecutar(new CrearRolCommand(request.nombre(), request.descripcion()));
    }

    @GetMapping("/permissions")
    public Flux<PermisoDTO> listarPermisos() {
        return listarPermisosUseCase.ejecutar();
    }

    // --- Request objects ---

    public record CrearUsuarioRequest(
            @NotBlank @Email String email,
            @NotBlank String nombre,
            @NotBlank String passwordTemporal) {}

    public record AsignarRolRequest(@NotBlank UUID rolId) {}

    public record CrearRolRequest(@NotBlank String nombre, String descripcion) {}
}
