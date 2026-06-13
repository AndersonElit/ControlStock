# Software Requirements Specification (SRS)

**Proyecto:** ControlStock
**Versión:** 1.0
**Fecha:** 2026-06-12
**Estado:** Borrador — Pendiente de aprobación

---

## 1. Introducción

### Propósito del Sistema

ControlStock es un sistema centralizado de gestión de inventario diseñado para reemplazar los procesos manuales, hojas de cálculo y aplicaciones no integradas con las que opera actualmente la organización. El sistema proveerá control en tiempo real de existencias, trazabilidad completa de movimientos y automatización de procesos críticos de abastecimiento.

### Objetivo del Documento

Este documento define los requerimientos funcionales y no funcionales del sistema ControlStock, establece las reglas de negocio aplicables, describe los casos de uso principales y fija los criterios de aceptación que servirán de base para la etapa de diseño técnico, desarrollo y pruebas.

### Alcance General

El sistema abarca la administración del catálogo de productos, control de stock en tiempo real, registro de movimientos de inventario (entradas, salidas y ajustes), historial de movimientos por producto (Kardex), gestión de proveedores, alertas automáticas configurables, dashboard ejecutivo con KPIs, reportería exportable, auditoría de operaciones, integración con servicios de notificación y proveedores externos, exposición de APIs REST y gestión de usuarios con control de acceso basado en roles (RBAC).

Quedan fuera del alcance de esta versión: sistemas contables, facturación electrónica, módulos CRM o ERP, aplicaciones móviles nativas e integración con plataformas de e-commerce.

### Contexto de Negocio

La organización opera en el dominio de Retail / Gestión de Inventario y Logística. La ausencia de un sistema centralizado genera inconsistencias en la información de existencias, falta de trazabilidad, errores recurrentes en registros manuales y costos operativos elevados por reprocesos. ControlStock busca eliminar estas deficiencias y establecer una base de datos confiable para la toma de decisiones en todos los niveles organizacionales.

---

## 2. Descripción General del Sistema

ControlStock es una aplicación web responsive que centraliza la gestión operativa y estratégica del inventario. El sistema permite a operadores registrar en tiempo real cada movimiento de mercancía, a supervisores configurar alertas y aprobar ajustes, y a gerentes consultar dashboards e informes con indicadores clave de desempeño.

### Procesos Principales

- **Gestión del catálogo:** alta, modificación, inactivación y categorización de productos.
- **Control de stock:** seguimiento en tiempo real de existencias por producto.
- **Movimientos de inventario:** registro de entradas (compras, devoluciones), salidas (ventas, consumos) y ajustes (correcciones, mermas).
- **Alertas automáticas:** notificaciones configurables ante condiciones críticas de stock.
- **Reportería y dashboards:** generación de reportes operativos y gerenciales exportables.
- **Integración externa:** comunicación con proveedores y servicios de notificación mediante APIs REST.
- **Auditoría:** registro inmutable de todas las operaciones del sistema.

### Contexto Operacional

El sistema opera sobre infraestructura cloud definida por la organización, bajo comunicación HTTPS/TLS. Los usuarios acceden mediante navegador web. Las integraciones externas se realizan a través de APIs REST estándar con formato JSON. El sistema soporta múltiples roles con permisos diferenciados.

---

## 3. Actores del Sistema

| Actor                    | Descripción                                                         | Responsabilidades Principales                                                         |
|--------------------------|---------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| Operador de Inventario   | Usuario operativo que gestiona las transacciones diarias            | Registrar entradas, salidas y ajustes de inventario; consultar stock y Kardex         |
| Supervisor de Inventario | Usuario con privilegios de supervisión sobre operaciones e informes | Aprobar ajustes, configurar alertas, revisar movimientos, acceder a reportes operativos |
| Administrador del Sistema | Usuario técnico-funcional con control total sobre configuración    | Gestionar usuarios, roles, permisos, proveedores y configuración del sistema          |
| Gerente / Analista       | Usuario estratégico consumidor de información                       | Consultar dashboard de KPIs y generar reportes gerenciales exportables                |
| Proveedor Externo        | Sistema o servicio externo integrado vía API                        | Proveer disponibilidad de productos y recibir solicitudes de abastecimiento           |
| Sistema de Notificaciones | Servicio externo de envío de alertas (email, mensajería)           | Recibir y distribuir notificaciones generadas por el sistema                          |
| Sistema Externo (API)    | Aplicación de terceros que consume la API pública de ControlStock   | Consultar y actualizar información de inventario mediante APIs REST                   |

---

## 4. Requerimientos Funcionales

### RF-001 — Autenticación de Usuarios

Descripción:
El sistema debe permitir que los usuarios accedan mediante credenciales (nombre de usuario o correo electrónico y contraseña). Las sesiones deben tener un tiempo de expiración configurable. El sistema debe soportar recuperación de contraseña mediante correo electrónico.

---

### RF-002 — Gestión de Usuarios

Descripción:
El sistema debe permitir al Administrador crear, modificar, activar e inactivar cuentas de usuario. Cada usuario debe tener asignado al menos un rol. Un usuario inactivo no puede autenticarse en el sistema.

---

### RF-003 — Gestión de Roles y Permisos (RBAC)

Descripción:
El sistema debe implementar control de acceso basado en roles. El Administrador puede crear roles, asignar permisos granulares a cada rol y asignar roles a usuarios. Los permisos deben aplicarse a nivel de módulo y operación (leer, crear, modificar, ejecutar).

---

### RF-004 — Gestión del Catálogo de Productos

Descripción:
El sistema debe permitir crear, modificar e inactivar productos en el catálogo. Cada producto debe registrar como mínimo: código único, nombre, descripción, categoría, unidad de medida, stock actual, stock mínimo, stock máximo y estado (activo/inactivo). Un producto inactivo no puede recibir nuevos movimientos.

---

### RF-005 — Gestión de Categorías de Productos

Descripción:
El sistema debe permitir crear, modificar e inactivar categorías de productos. Cada producto debe estar asociado a exactamente una categoría. Una categoría con productos activos asociados no puede inactivarse.

---

### RF-006 — Control de Stock en Tiempo Real

Descripción:
El sistema debe mantener y mostrar el stock disponible actualizado de cada producto inmediatamente después de cada movimiento registrado. La consulta de stock debe reflejar el estado real sin necesidad de recarga manual.

---

### RF-007 — Registro de Entradas de Inventario

Descripción:
El sistema debe permitir registrar entradas de productos al inventario. Cada entrada debe incluir: producto, cantidad, fecha, motivo o tipo de entrada (compra, devolución de cliente, ajuste de apertura u otro), referencia del documento origen y usuario responsable. El stock del producto debe actualizarse automáticamente al registrar la entrada.

---

### RF-008 — Registro de Salidas de Inventario

Descripción:
El sistema debe permitir registrar salidas de productos del inventario. Cada salida debe incluir: producto, cantidad, fecha, motivo o tipo de salida (venta, consumo interno, merma u otro), referencia del documento origen y usuario responsable. El sistema debe impedir registrar una salida si la cantidad solicitada supera el stock disponible. El stock se actualiza automáticamente al confirmar la salida.

---

### RF-009 — Registro de Ajustes de Inventario

Descripción:
El sistema debe permitir registrar ajustes de inventario para corregir discrepancias entre el stock físico y el registrado. Cada ajuste debe incluir: producto, cantidad ajustada (positiva o negativa), motivo obligatorio, usuario responsable y fecha. Los ajustes requieren aprobación del Supervisor o Administrador antes de impactar el stock.

---

### RF-010 — Consulta de Historial de Movimientos (Kardex)

Descripción:
El sistema debe mostrar el historial cronológico completo de movimientos de un producto: entradas, salidas y ajustes, con saldo acumulado después de cada movimiento. El Kardex debe ser filtrable por producto, tipo de movimiento, rango de fechas y usuario responsable.

---

### RF-011 — Configuración de Stock Mínimo y Máximo

Descripción:
El sistema debe permitir configurar para cada producto un umbral de stock mínimo y un umbral de stock máximo. Estos valores son utilizados por el motor de alertas para generar notificaciones automáticas. El stock máximo debe ser mayor que el stock mínimo en todo momento.

---

### RF-012 — Alertas Automáticas de Inventario

Descripción:
El sistema debe evaluar el stock de cada producto tras cada movimiento y generar alertas automáticas cuando se cumplan las siguientes condiciones:
- Stock disponible ≤ stock mínimo configurado (alerta de bajo stock).
- Stock disponible ≥ stock máximo configurado (alerta de sobrestock).
- Producto próximo a vencer (cuando aplique fecha de vencimiento).

Las alertas deben quedar registradas en el sistema y enviarse a través del servicio de notificaciones configurado.

---

### RF-013 — Gestión de Proveedores

Descripción:
El sistema debe permitir registrar, modificar e inactivar proveedores. Cada proveedor debe incluir: nombre, identificación fiscal, datos de contacto, método de integración disponible (API REST o intercambio de archivos) y estado. Un proveedor con movimientos de inventario asociados no puede eliminarse del sistema.

---

### RF-014 — Dashboard Ejecutivo de KPIs

Descripción:
El sistema debe proveer un dashboard con indicadores clave de inventario actualizados en tiempo real. Los KPIs mínimos a mostrar son: total de productos activos, productos con stock bajo mínimo, valor total del inventario, movimientos del período actual (entradas, salidas, ajustes), top productos con mayor rotación y alertas activas pendientes.

---

### RF-015 — Generación de Reportes

Descripción:
El sistema debe permitir generar los siguientes reportes parametrizables por rango de fechas y filtros adicionales:
- Reporte de stock actual por producto y categoría.
- Reporte de movimientos de inventario por período.
- Reporte de Kardex por producto.
- Reporte de productos bajo stock mínimo.
- Reporte de proveedores y su actividad.
- Reporte de auditoría de operaciones.

---

### RF-016 — Exportación de Reportes

Descripción:
El sistema debe permitir exportar cualquier reporte generado en al menos los formatos PDF y Excel (XLSX). La exportación debe preservar la estructura, filtros aplicados y datos completos del reporte.

---

### RF-017 — Auditoría de Operaciones

Descripción:
El sistema debe registrar de forma automática e inmutable toda operación realizada: creación, modificación, inactivación de entidades y ejecución de movimientos de inventario. Cada registro de auditoría debe incluir: fecha y hora, usuario responsable, operación ejecutada, entidad afectada y valores anterior y posterior cuando aplique. El registro de auditoría no puede modificarse ni eliminarse.

---

### RF-018 — Integración con Servicios de Notificación

Descripción:
El sistema debe integrarse con al menos un servicio externo de notificaciones (correo electrónico y/o mensajería) para el envío de alertas automáticas de inventario. La configuración del proveedor de notificaciones debe ser administrable sin cambios en el código. El sistema debe registrar el estado de entrega de cada notificación enviada.

---

### RF-019 — Integración con Proveedores Externos

Descripción:
El sistema debe soportar integración con proveedores externos para consultar disponibilidad de productos y enviar solicitudes de reposición. La integración se realizará mediante APIs REST o intercambio de archivos según lo que disponga cada proveedor. El resultado de cada intercambio debe quedar registrado en el sistema.

---

### RF-020 — Exposición de API REST

Descripción:
El sistema debe exponer una API REST documentada que permita a sistemas externos consultar el stock disponible por producto, registrar movimientos de inventario y obtener el Kardex de un producto. Todos los accesos a la API requieren autenticación mediante token. Los permisos de la API deben ser administrables mediante el módulo RBAC.

---

## 5. Requerimientos No Funcionales

### RNF-001 — Disponibilidad

Categoría: Disponibilidad

El sistema debe mantener una disponibilidad mínima del 99,9% medida mensualmente en el entorno de producción. Los mantenimientos programados deben ejecutarse fuera del horario operativo y notificarse con al menos 48 horas de anticipación.

---

### RNF-002 — Rendimiento

Categoría: Rendimiento

El sistema debe responder el 95% de las solicitudes de consulta de inventario y Kardex en menos de 2 segundos bajo carga normal. Las operaciones de registro de movimientos deben completarse en menos de 3 segundos. La generación de reportes complejos puede extenderse hasta 10 segundos.

---

### RNF-003 — Escalabilidad

Categoría: Escalabilidad

El sistema debe soportar al menos 500 usuarios concurrentes sin degradación del rendimiento. La arquitectura debe permitir escalar horizontalmente los componentes de mayor carga sin rediseño estructural.

---

### RNF-004 — Seguridad — Autenticación y Autorización

Categoría: Seguridad

Todas las funcionalidades del sistema deben estar protegidas por autenticación. El control de acceso debe implementarse mediante RBAC con permisos granulares por módulo y operación. Los tokens de sesión deben tener expiración configurable y soporte para revocación inmediata.

---

### RNF-005 — Seguridad — Comunicación

Categoría: Seguridad

Toda comunicación entre clientes y el servidor, y entre el servidor y servicios externos, debe realizarse mediante HTTPS/TLS. No se permite tráfico HTTP no cifrado en ningún entorno productivo.

---

### RNF-006 — Seguridad — Protección de Datos

Categoría: Seguridad

Las contraseñas de usuarios deben almacenarse con algoritmo de hash seguro (bcrypt o equivalente). Los datos sensibles de proveedores y credenciales de integración deben almacenarse cifrados. El sistema debe cumplir las políticas de seguridad corporativas vigentes.

---

### RNF-007 — Usabilidad

Categoría: Usabilidad

La interfaz de usuario debe ser responsive y funcionar correctamente en navegadores de escritorio y dispositivos móviles con resoluciones estándar. Los flujos principales (registro de movimiento, consulta de stock, generación de reporte) deben completarse en no más de 4 pasos desde el menú principal. El sistema debe mostrar mensajes de error claros y accionables.

---

### RNF-008 — Mantenibilidad

Categoría: Mantenibilidad

El sistema debe desarrollarse con arquitectura modular que permita modificar o extender módulos individuales sin impacto en el resto del sistema. El código debe seguir prácticas de DDD, con separación clara entre dominio, aplicación e infraestructura.

---

### RNF-009 — Observabilidad

Categoría: Observabilidad

El sistema debe exponer métricas operativas, logs estructurados y trazabilidad distribuida centralizados en la plataforma de observabilidad definida por la organización. Las métricas mínimas a instrumentar son: latencia por endpoint, tasa de errores, uso de recursos y alertas activas del sistema.

---

### RNF-010 — Despliegue

Categoría: Portabilidad / Despliegue

El sistema debe desplegarse sobre la infraestructura cloud definida por la organización, con soporte para integración continua y entrega continua (CI/CD). El proceso de despliegue debe ser reproducible, automatizable y documentado.

---

## 6. Reglas de Negocio

- **RN-001:** Solo usuarios autenticados y con el rol correspondiente pueden acceder a cada módulo del sistema.
- **RN-002:** Los movimientos de inventario registrados (entradas, salidas) no pueden eliminarse. Solo pueden anularse por un usuario con permiso explícito, quedando el movimiento visible con estado "anulado" en el Kardex.
- **RN-003:** El sistema no permite registrar una salida de inventario si la cantidad solicitada supera el stock disponible del producto en ese momento.
- **RN-004:** Cuando el stock de un producto alcanza o cae por debajo del mínimo configurado, el sistema genera automáticamente una alerta y la envía al servicio de notificaciones.
- **RN-005:** Los ajustes de inventario requieren motivo obligatorio y aprobación de un usuario con rol Supervisor o Administrador antes de impactar el stock.
- **RN-006:** Un producto inactivo no puede recibir nuevos movimientos de inventario.
- **RN-007:** El stock máximo configurado para un producto debe ser siempre mayor que el stock mínimo. El sistema debe impedir guardar una configuración que viole esta condición.
- **RN-008:** Un proveedor que tenga movimientos de inventario asociados no puede eliminarse del sistema. Solo puede inactivarse.
- **RN-009:** Los reportes gerenciales y el dashboard ejecutivo son accesibles únicamente a usuarios con roles que tengan permiso explícito de lectura sobre esos módulos.
- **RN-010:** Todo movimiento de inventario queda registrado de forma inmediata e inmutable en el Kardex del producto afectado.
- **RN-011:** El registro de auditoría no puede ser modificado ni eliminado por ningún usuario ni proceso del sistema.
- **RN-012:** Una categoría de productos no puede inactivarse si tiene productos activos asociados.

---

## 7. Casos de Uso Principales

### CU-001 — Registrar Entrada de Inventario

Actores: Operador de Inventario

Precondiciones:
- Usuario autenticado con permiso de registro de entradas.
- El producto existe y está activo en el catálogo.

Flujo principal:
1. El operador selecciona la opción "Registrar entrada" en el módulo de inventario.
2. El operador busca y selecciona el producto.
3. El operador ingresa la cantidad, tipo de entrada, referencia del documento origen y fecha.
4. El sistema valida los datos ingresados.
5. El sistema actualiza el stock disponible del producto.
6. El sistema registra el movimiento en el Kardex.
7. El sistema verifica si el nuevo stock supera el máximo configurado y genera alerta si corresponde.

Resultado esperado:
Entrada registrada correctamente; stock del producto actualizado en tiempo real; movimiento visible en el Kardex.

---

### CU-002 — Registrar Salida de Inventario

Actores: Operador de Inventario

Precondiciones:
- Usuario autenticado con permiso de registro de salidas.
- El producto existe, está activo y tiene stock suficiente.

Flujo principal:
1. El operador selecciona la opción "Registrar salida" en el módulo de inventario.
2. El operador busca y selecciona el producto.
3. El operador ingresa la cantidad, tipo de salida, referencia del documento origen y fecha.
4. El sistema verifica que el stock disponible sea igual o mayor a la cantidad solicitada.
5. El sistema actualiza el stock disponible del producto.
6. El sistema registra el movimiento en el Kardex.
7. El sistema verifica si el nuevo stock es igual o inferior al mínimo configurado y genera alerta si corresponde.

Resultado esperado:
Salida registrada; stock actualizado; movimiento visible en el Kardex.

---

### CU-003 — Registrar Ajuste de Inventario

Actores: Operador de Inventario, Supervisor de Inventario

Precondiciones:
- Usuario autenticado con permiso de creación de ajustes.
- El producto existe y está activo.

Flujo principal:
1. El operador selecciona "Registrar ajuste" en el módulo de inventario.
2. El operador selecciona el producto, ingresa la cantidad de ajuste (positiva o negativa) y el motivo obligatorio.
3. El sistema guarda el ajuste en estado "Pendiente de aprobación".
4. El Supervisor recibe notificación de ajuste pendiente.
5. El Supervisor revisa el ajuste y lo aprueba o rechaza con comentario.
6. Si aprobado: el sistema actualiza el stock y registra el movimiento en el Kardex.
7. Si rechazado: el ajuste queda en estado "Rechazado" sin impacto en el stock.

Resultado esperado:
Ajuste aprobado y stock actualizado; o ajuste rechazado sin modificación de stock.

---

### CU-004 — Consultar Kardex de Producto

Actores: Operador de Inventario, Supervisor de Inventario, Gerente / Analista

Precondiciones:
- Usuario autenticado con permiso de consulta de inventario.

Flujo principal:
1. El usuario accede al módulo de consulta de inventario.
2. El usuario busca y selecciona el producto.
3. El usuario aplica filtros opcionales: rango de fechas, tipo de movimiento.
4. El sistema presenta el historial cronológico de movimientos con saldo acumulado.

Resultado esperado:
Historial completo del producto mostrado con saldo tras cada movimiento.

---

### CU-005 — Configurar Alertas de Stock

Actores: Supervisor de Inventario, Administrador del Sistema

Precondiciones:
- Usuario autenticado con permiso de configuración de inventario.
- El producto existe y está activo.

Flujo principal:
1. El supervisor accede a la configuración del producto.
2. El supervisor define o modifica el stock mínimo y stock máximo.
3. El sistema valida que el máximo sea mayor que el mínimo.
4. El sistema guarda la configuración y la activa para el motor de alertas.

Resultado esperado:
Umbrales configurados; el motor de alertas evaluará el stock del producto contra los nuevos umbrales en cada movimiento.

---

### CU-006 — Generar Reporte Gerencial

Actores: Gerente / Analista, Supervisor de Inventario

Precondiciones:
- Usuario autenticado con permiso de acceso a reportería.

Flujo principal:
1. El usuario accede al módulo de reportes.
2. El usuario selecciona el tipo de reporte.
3. El usuario define los parámetros: rango de fechas, categoría, producto u otros filtros disponibles.
4. El sistema genera el reporte con los datos correspondientes.
5. El usuario descarga el reporte en el formato seleccionado (PDF o XLSX).

Resultado esperado:
Reporte generado y descargado correctamente con los datos filtrados.

---

### CU-007 — Gestionar Catálogo de Productos

Actores: Administrador del Sistema, Supervisor de Inventario

Precondiciones:
- Usuario autenticado con permiso de administración del catálogo.

Flujo principal:
1. El administrador accede al módulo de catálogo de productos.
2. El administrador crea un nuevo producto o selecciona uno existente para modificarlo.
3. El administrador ingresa o actualiza los campos requeridos: código, nombre, categoría, unidad de medida, stock mínimo y máximo.
4. El sistema valida unicidad del código y consistencia de los umbrales.
5. El sistema guarda el producto y lo hace disponible para operaciones de inventario.

Resultado esperado:
Producto creado o actualizado correctamente y disponible en el catálogo.

---

### CU-008 — Integrar Proveedor Externo

Actores: Administrador del Sistema, Sistema del Proveedor Externo

Precondiciones:
- Proveedor registrado y activo en el sistema.
- Método de integración configurado (API REST o archivo).

Flujo principal:
1. El sistema (o el Administrador manualmente) inicia el proceso de integración con el proveedor.
2. El sistema envía la solicitud de disponibilidad o reposición según el método configurado.
3. El proveedor responde con los datos de disponibilidad o confirmación del pedido.
4. El sistema registra el resultado de la integración.
5. Si se recibe confirmación de entrada de mercancía, el sistema genera el movimiento de entrada correspondiente.

Resultado esperado:
Integración ejecutada; resultado registrado; stock actualizado si corresponde.

---

## 8. Restricciones Técnicas

- **Plataforma:** Aplicación web responsive. No se desarrollará aplicación móvil nativa en esta fase.
- **Protocolos de integración:** Las integraciones externas deben utilizar APIs REST con formato JSON. Se admite intercambio de archivos como alternativa para proveedores sin capacidad API.
- **Infraestructura:** El sistema debe desplegarse en la infraestructura cloud definida y aprobada por el Área de TI de la organización.
- **Seguridad:** La solución debe cumplir con las políticas de seguridad corporativas vigentes, incluyendo gestión de secretos, cifrado en tránsito y en reposo.
- **Metodología de desarrollo:** El proyecto utilizará prácticas de DDD, BDD y ATDD. El flujo de entrega debe implementar CI/CD desde las etapas iniciales.
- **Autenticación API:** El acceso a la API REST expuesta debe autenticarse mediante tokens (JWT u OAuth 2.0 según definición en diseño técnico).

---

## 9. Supuestos y Dependencias

### Supuestos

- Los proveedores con los que se integrará el sistema disponen de mecanismos tecnológicos habilitados (APIs REST o capacidad de intercambio de archivos) para la integración.
- Los usuarios operativos y supervisores recibirán capacitación formal antes del despliegue a producción.
- La infraestructura cloud estará disponible y operativa durante todo el ciclo de desarrollo y pruebas.
- Existe conectividad estable y permanente desde la infraestructura del sistema hacia los servicios externos requeridos (notificaciones, proveedores).
- La organización designará un Project Manager antes del inicio formal de la etapa de desarrollo.
- Los datos actuales de inventario en hojas de cálculo y sistemas dispersos son exportables y susceptibles de migración al nuevo sistema.
- El Área de TI proveerá acceso a los entornos cloud y herramientas de infraestructura necesarias dentro de los plazos del proyecto.

### Dependencias Externas

- Servicio externo de notificaciones (email y/o mensajería) para el envío de alertas automáticas.
- APIs o mecanismos de intercambio de información de proveedores externos.
- Infraestructura cloud corporativa (cómputo, almacenamiento, red, bases de datos).
- Plataforma de observabilidad centralizada (métricas, logs, trazas) definida por el Área de TI.
- Servicio de autenticación corporativo, si la organización define integrar SSO en fases posteriores.

---

## 10. Criterios de Aceptación

### RF-001 — Autenticación de Usuarios

Criterios de aceptación:
- Un usuario registrado puede autenticarse con credenciales válidas y acceder al sistema.
- El sistema rechaza credenciales incorrectas e informa al usuario sin revelar si el error es en el usuario o la contraseña.
- La sesión expira automáticamente tras el tiempo de inactividad configurado.
- El flujo de recuperación de contraseña envía el enlace al correo del usuario y el enlace expira en el tiempo definido.

---

### RF-004 — Gestión del Catálogo de Productos

Criterios de aceptación:
- Se puede crear un producto con todos sus campos obligatorios y queda disponible para registrar movimientos.
- El sistema rechaza la creación de un producto con código duplicado.
- Un producto inactivo no aparece en las opciones de selección para registrar movimientos.
- La modificación de un producto actualiza la información inmediatamente en todas las consultas del sistema.

---

### RF-007 — Registro de Entradas de Inventario

Criterios de aceptación:
- Al registrar una entrada, el stock del producto aumenta en la cantidad indicada de forma inmediata.
- El movimiento queda registrado en el Kardex con todos sus atributos: fecha, tipo, cantidad, saldo y usuario.
- El sistema no permite registrar una entrada con cantidad igual o menor a cero.
- Si el stock supera el máximo configurado tras la entrada, se genera una alerta visible en el dashboard.

---

### RF-008 — Registro de Salidas de Inventario

Criterios de aceptación:
- Al registrar una salida, el stock del producto disminuye en la cantidad indicada de forma inmediata.
- El sistema rechaza la salida si la cantidad solicitada supera el stock disponible, mostrando el stock actual al usuario.
- Si el stock cae al nivel mínimo o por debajo, el sistema genera una alerta y la envía al servicio de notificaciones.
- El movimiento queda registrado en el Kardex con saldo actualizado.

---

### RF-009 — Registro de Ajustes de Inventario

Criterios de aceptación:
- Un ajuste creado por el operador queda en estado "Pendiente" sin modificar el stock.
- El Supervisor puede aprobar o rechazar ajustes pendientes.
- Solo al aprobarse el ajuste el stock del producto se actualiza.
- Todo ajuste rechazado queda registrado en auditoría con el motivo de rechazo.
- El campo de motivo es obligatorio; el sistema impide guardar un ajuste sin motivo.

---

### RF-012 — Alertas Automáticas de Inventario

Criterios de aceptación:
- Cuando el stock de un producto baja al umbral mínimo o por debajo, se genera automáticamente una alerta visible en el dashboard y se envía notificación al canal configurado.
- Cuando el stock supera el umbral máximo, se genera alerta de sobrestock.
- Las alertas quedan registradas en el sistema con fecha, producto y tipo de alerta.
- Si el servicio de notificaciones externo no está disponible, el sistema registra el intento fallido y reintenta según política configurada.

---

### RF-015 — Generación de Reportes

Criterios de aceptación:
- El reporte de stock actual muestra todos los productos activos con su stock real al momento de la generación.
- El reporte de movimientos filtra correctamente por rango de fechas y tipo de movimiento.
- El reporte de Kardex refleja la trazabilidad completa del producto con saldos consistentes.
- Los reportes exportados en PDF y XLSX contienen los mismos datos que los visualizados en pantalla.

---

### RF-017 — Auditoría de Operaciones

Criterios de aceptación:
- Toda operación de creación, modificación o inactivación queda registrada con usuario, fecha, hora y valores antes/después.
- El registro de auditoría no puede ser modificado ni eliminado por ningún usuario.
- El reporte de auditoría es accesible únicamente a usuarios con permiso explícito.

---

### RF-020 — Exposición de API REST

Criterios de aceptación:
- Un sistema externo autenticado con token válido puede consultar el stock de un producto y recibir respuesta en formato JSON.
- Una solicitud sin token o con token inválido recibe respuesta HTTP 401.
- Un token sin permiso para una operación específica recibe respuesta HTTP 403.
- La API devuelve respuestas de error estructuradas con código y mensaje descriptivo.

---

## 11. Glosario

| Término                  | Definición                                                                                                           |
|--------------------------|----------------------------------------------------------------------------------------------------------------------|
| Stock                    | Cantidad disponible de un producto en inventario en un momento determinado.                                          |
| Kardex                   | Registro histórico cronológico de todos los movimientos de un producto, con saldo acumulado tras cada operación.     |
| Entrada de inventario    | Movimiento que incrementa el stock de un producto (compra, devolución de cliente, ajuste de apertura).               |
| Salida de inventario     | Movimiento que reduce el stock de un producto (venta, consumo interno, merma).                                       |
| Ajuste de inventario     | Corrección de discrepancias entre el stock físico real y el stock registrado en el sistema.                          |
| Stock mínimo             | Umbral inferior de stock por debajo del cual se genera una alerta de bajo stock para un producto.                    |
| Stock máximo             | Umbral superior de stock por encima del cual se genera una alerta de sobrestock para un producto.                    |
| RBAC                     | Role-Based Access Control. Modelo de control de acceso basado en roles con permisos asignados por rol.               |
| KPI                      | Key Performance Indicator. Indicador clave de desempeño utilizado para medir el estado del inventario.               |
| SLA                      | Service Level Agreement. Acuerdo de nivel de servicio que define compromisos de disponibilidad y rendimiento.        |
| API REST                 | Interfaz de programación de aplicaciones basada en el protocolo HTTP con estilo arquitectónico REST.                 |
| CI/CD                    | Continuous Integration / Continuous Delivery. Prácticas de automatización del ciclo de integración y despliegue.    |
| DDD                      | Domain-Driven Design. Enfoque de diseño de software centrado en el modelo del dominio de negocio.                    |
| BDD                      | Behavior-Driven Development. Técnica de desarrollo guiada por comportamientos definidos en lenguaje natural.         |
| ATDD                     | Acceptance Test-Driven Development. Enfoque donde los criterios de aceptación definen las pruebas antes del código.  |
| Sobrestock               | Condición en la que el stock de un producto supera el umbral máximo configurado.                                     |
| Trazabilidad             | Capacidad del sistema de rastrear el origen, historial y estado de cualquier operación o entidad registrada.         |
| Observabilidad           | Capacidad de monitorear el comportamiento interno del sistema a través de métricas, logs y trazas distribuidas.      |
| Proveedor externo        | Empresa o servicio que suministra productos al inventario y con quien se establece integración de datos.             |
| Go-live                  | Fecha de puesta en producción del sistema con usuarios reales.                                                       |

---

*Documento generado como parte de la etapa de Análisis de Requerimientos del SDLC — ControlStock.*
