package com.iamservice.model;

import com.iamservice.model.vo.PermisoId;

public class Permiso {
    private final PermisoId id;
    private final String modulo;
    private final String operacion;
    private final String descripcion;

    public Permiso(PermisoId id, String modulo, String operacion, String descripcion) {
        this.id = id;
        this.modulo = modulo;
        this.operacion = operacion;
        this.descripcion = descripcion;
    }

    public static Permiso crear(String modulo, String operacion, String descripcion) {
        return new Permiso(PermisoId.generate(), modulo, operacion, descripcion);
    }

    public PermisoId getId() { return id; }
    public String getModulo() { return modulo; }
    public String getOperacion() { return operacion; }
    public String getDescripcion() { return descripcion; }
}
