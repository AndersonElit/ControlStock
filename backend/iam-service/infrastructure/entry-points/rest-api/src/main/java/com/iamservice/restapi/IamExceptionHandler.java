package com.iamservice.restapi;

import com.iamservice.model.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.bind.support.WebExchangeBindException;
import reactor.core.publisher.Mono;

import java.util.stream.Collectors;

@RestControllerAdvice
public class IamExceptionHandler {

    @ExceptionHandler(UsuarioNoEncontradoException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleUsuarioNoEncontrado(UsuarioNoEncontradoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_NO_ENCONTRADO", ex.getMessage()));
    }

    @ExceptionHandler(EmailDuplicadoException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ErrorResponse> handleEmailDuplicado(EmailDuplicadoException ex) {
        return Mono.just(new ErrorResponse("EMAIL_DUPLICADO", ex.getMessage()));
    }

    @ExceptionHandler(UsuarioYaInactivoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleYaInactivo(UsuarioYaInactivoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_YA_INACTIVO", ex.getMessage()));
    }

    @ExceptionHandler(UsuarioInactivoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleInactivo(UsuarioInactivoException ex) {
        return Mono.just(new ErrorResponse("USUARIO_INACTIVO", ex.getMessage()));
    }

    @ExceptionHandler(RolNoEncontradoException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleRolNoEncontrado(RolNoEncontradoException ex) {
        return Mono.just(new ErrorResponse("ROL_NO_ENCONTRADO", ex.getMessage()));
    }

    @ExceptionHandler(RolNoAsignadoException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public Mono<ErrorResponse> handleRolNoAsignado(RolNoAsignadoException ex) {
        return Mono.just(new ErrorResponse("ROL_NO_ASIGNADO", ex.getMessage()));
    }

    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleValidation(WebExchangeBindException ex) {
        String mensaje = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining(", "));
        return Mono.just(new ErrorResponse("VALIDACION_FALLIDA", mensaje));
    }

    public record ErrorResponse(String code, String message) {}
}
