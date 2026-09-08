-- ═══════════════════════════════════════════════════════════════════════════
--  CAPA ADMINISTRATIVA — Lo que gestiona admin.html
--  Ejecutar después de 01_schema.sql:
--    psql "$DATABASE_URL" -f db/03_admin.sql
--
--  Cubre las nueve secciones del panel: hero, comercios, categorías, eventos,
--  galería, ubicación, textos y footer, usuarios y ajustes del sitio.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$ BEGIN
  CREATE TYPE estado_usuario AS ENUM ('activo', 'invitado', 'suspendido');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE accion_auditoria AS ENUM ('creo', 'actualizo', 'elimino', 'publico', 'inicio_sesion', 'cerro_sesion');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ═══════════════════════════════════════════════════════════════════════════
--  10. COLUMNAS QUE EL PANEL EDITA Y NO EXISTÍAN
--      El formulario de comercios guarda el horario como un texto libre
--      ("09:30 - 20:00") además del detalle por día de horarios_tienda:
--      el texto es lo que se muestra, la tabla es lo que se calcula.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE tiendas ADD COLUMN IF NOT EXISTS horario_texto varchar(80);
ALTER TABLE tiendas ADD COLUMN IF NOT EXISTS enlace        text;

COMMENT ON COLUMN tiendas.horario_texto IS 'Horario tal como se muestra en la ficha. El cálculo de "abierto ahora" usa horarios_tienda.';
COMMENT ON COLUMN tiendas.enlace        IS 'Destino del botón de la tarjeta: ficha interna, sitio propio o enlace de WhatsApp.';


-- ═══════════════════════════════════════════════════════════════════════════
--  11. ROLES, SECCIONES Y PERMISOS
--      La matriz reproduce exactamente SECCIONES_PERMISOS de admin.html.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS roles (
  id           int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre       varchar(60)  NOT NULL UNIQUE,
  slug         varchar(70)  NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  descripcion  text,
  clase_chip   varchar(40)  NOT NULL DEFAULT 'chip-off',
  es_sistema   boolean      NOT NULL DEFAULT false,
  orden        smallint     NOT NULL DEFAULT 0
);

COMMENT ON COLUMN roles.clase_chip IS 'Clase visual del distintivo en el panel, según el mapa ROL_CHIP.';
COMMENT ON COLUMN roles.es_sistema IS 'Los roles de sistema no pueden eliminarse desde el panel.';

CREATE TABLE IF NOT EXISTS secciones_panel (
  id      int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre  varchar(60)  NOT NULL UNIQUE,
  slug    varchar(70)  NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  icono   varchar(60),
  orden   smallint     NOT NULL DEFAULT 0
);

-- Un rol accede o no a cada sección. La ausencia de fila equivale a "sin acceso",
-- pero se guardan ambos valores para que el panel pinte la matriz completa.
CREATE TABLE IF NOT EXISTS permisos_rol (
  rol_id      int     NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  seccion_id  int     NOT NULL REFERENCES secciones_panel(id) ON DELETE CASCADE,
  puede_ver   boolean NOT NULL DEFAULT false,
  puede_editar boolean NOT NULL DEFAULT false,
  PRIMARY KEY (rol_id, seccion_id),
  -- No se puede editar aquello que no se puede ver.
  CONSTRAINT ck_permiso_coherente CHECK (puede_ver OR NOT puede_editar)
);


-- ═══════════════════════════════════════════════════════════════════════════
--  12. USUARIOS DEL PANEL
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS usuarios_admin (
  id                  int            GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre              varchar(120)   NOT NULL,
  email               varchar(150)   NOT NULL UNIQUE CHECK (email LIKE '%_@_%._%'),
  rol_id              int            NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,

  -- NUNCA guardar la contraseña en claro. Este campo almacena el resultado de
  -- bcrypt o argon2 calculado por la aplicación, jamás el texto escrito.
  -- Queda NULL mientras la invitación está pendiente de aceptar.
  contrasena_hash     text,

  foto_url            text,
  estado              estado_usuario NOT NULL DEFAULT 'invitado',

  -- Verificación en dos pasos
  doble_factor_activo  boolean       NOT NULL DEFAULT false,
  doble_factor_secreto text,

  -- Invitación
  invitado_por_id     int            REFERENCES usuarios_admin(id) ON DELETE SET NULL,
  invitacion_token    text           UNIQUE,
  invitacion_expira   timestamptz,

  ultimo_acceso       timestamptz,
  creado_en           timestamptz    NOT NULL DEFAULT now(),
  actualizado_en      timestamptz    NOT NULL DEFAULT now(),

  -- Una cuenta activa siempre tiene contraseña; una invitada todavía no.
  CONSTRAINT ck_usuario_activo_con_clave CHECK (
    estado <> 'activo' OR contrasena_hash IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS ix_usuarios_rol    ON usuarios_admin (rol_id);
CREATE INDEX IF NOT EXISTS ix_usuarios_estado ON usuarios_admin (estado);

DROP TRIGGER IF EXISTS tg_usuarios_actualizacion ON usuarios_admin;
CREATE TRIGGER tg_usuarios_actualizacion
  BEFORE UPDATE ON usuarios_admin
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();

COMMENT ON COLUMN usuarios_admin.doble_factor_secreto IS 'Semilla TOTP. Debe guardarse cifrada por la aplicación, no en claro.';


-- ═══════════════════════════════════════════════════════════════════════════
--  13. SESIONES ACTIVAS
--      Alimenta el listado "Sesiones activas" y permite cerrarlas a distancia.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sesiones_admin (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id     int          NOT NULL REFERENCES usuarios_admin(id) ON DELETE CASCADE,

  -- Se guarda el hash del token, no el token: si alguien lee la tabla no puede
  -- suplantar sesiones con lo que encuentre.
  token_hash     text         NOT NULL UNIQUE,

  ip             inet,
  navegador      text,
  dispositivo    varchar(80),

  creada_en      timestamptz  NOT NULL DEFAULT now(),
  ultima_actividad timestamptz NOT NULL DEFAULT now(),
  expira_en      timestamptz  NOT NULL,
  cerrada_en     timestamptz,

  CONSTRAINT ck_sesion_vigencia CHECK (expira_en > creada_en)
);

CREATE INDEX IF NOT EXISTS ix_sesiones_usuario ON sesiones_admin (usuario_id);
CREATE INDEX IF NOT EXISTS ix_sesiones_activas ON sesiones_admin (expira_en) WHERE cerrada_en IS NULL;


-- ═══════════════════════════════════════════════════════════════════════════
--  14. AUDITORÍA
--      Alimenta "Actividad reciente" y "Historial de mis cambios".
--      datos_antes / datos_despues guardan el registro en JSON para poder
--      mostrar qué cambió exactamente y, si hace falta, revertirlo.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS auditoria (
  id             bigint           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id     int              REFERENCES usuarios_admin(id) ON DELETE SET NULL,
  usuario_nombre varchar(120),
  accion         accion_auditoria NOT NULL,
  entidad        varchar(60)      NOT NULL,
  entidad_id     int,
  resumen        text,
  datos_antes    jsonb,
  datos_despues  jsonb,
  ip             inet,
  ocurrido_en    timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_auditoria_fecha   ON auditoria (ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS ix_auditoria_usuario ON auditoria (usuario_id, ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS ix_auditoria_entidad ON auditoria (entidad, entidad_id);

COMMENT ON COLUMN auditoria.usuario_nombre IS 'Nombre copiado al momento del hecho: el historial sobrevive al borrado de la cuenta.';


-- ═══════════════════════════════════════════════════════════════════════════
--  15. GALERÍA DE IMÁGENES
--      Sección "Galería" y medidor de "Almacenamiento" del panel.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS archivos (
  id            int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre        varchar(200) NOT NULL,
  url           text         NOT NULL,
  tipo_mime     varchar(100),
  tamano_bytes  bigint       CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0),
  ancho_px      int,
  alto_px       int,
  texto_alt     varchar(200),
  subido_por_id int          REFERENCES usuarios_admin(id) ON DELETE SET NULL,
  creado_en     timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_archivos_fecha ON archivos (creado_en DESC);

COMMENT ON COLUMN archivos.texto_alt IS 'Texto alternativo para lectores de pantalla. Conviene exigirlo al subir.';


-- ═══════════════════════════════════════════════════════════════════════════
--  16. DIAPOSITIVAS DEL HERO
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS hero_slides (
  id             int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- El título actúa como clave natural: permite recargar la semilla sin duplicar.
  titulo         varchar(160) NOT NULL UNIQUE,
  descripcion    text,
  imagen_url     text         NOT NULL,
  icono          varchar(60),
  texto_boton    varchar(60),
  enlace         text,
  activo         boolean      NOT NULL DEFAULT true,
  orden          smallint     NOT NULL DEFAULT 0,
  creado_en      timestamptz  NOT NULL DEFAULT now(),
  actualizado_en timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_hero_activos ON hero_slides (orden) WHERE activo;

DROP TRIGGER IF EXISTS tg_hero_actualizacion ON hero_slides;
CREATE TRIGGER tg_hero_actualizacion
  BEFORE UPDATE ON hero_slides
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();


-- ═══════════════════════════════════════════════════════════════════════════
--  17. AJUSTES DEL SITIO
--      Los textos sueltos que edita el panel (SEO, footer, franja de
--      beneficios, barra superior, identidad visual, mantenimiento) son
--      demasiados y demasiado cambiantes para merecer una columna cada uno.
--      Van como pares clave-valor agrupados por sección; los datos duros
--      —dirección, teléfono, coordenadas— siguen en configuracion_sitio.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ajustes_sitio (
  clave          varchar(80)  PRIMARY KEY CHECK (clave ~ '^[a-z0-9_.]+$'),
  valor          text,
  grupo          varchar(40)  NOT NULL DEFAULT 'general',
  etiqueta       varchar(120),
  tipo           varchar(20)  NOT NULL DEFAULT 'texto'
                 CHECK (tipo IN ('texto', 'texto_largo', 'numero', 'booleano', 'url', 'color', 'json')),
  actualizado_en timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ajustes_grupo ON ajustes_sitio (grupo);

DROP TRIGGER IF EXISTS tg_ajustes_actualizacion ON ajustes_sitio;
CREATE TRIGGER tg_ajustes_actualizacion
  BEFORE UPDATE ON ajustes_sitio
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();

COMMENT ON TABLE ajustes_sitio IS 'Textos y banderas editables del panel. tipo indica qué control mostrar en el formulario.';


-- ═══════════════════════════════════════════════════════════════════════════
--  18. VISTA: permisos en forma de matriz, como los pinta el panel
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW vw_matriz_permisos AS
SELECT
  s.nombre    AS seccion,
  s.orden     AS seccion_orden,
  r.nombre    AS rol,
  r.orden     AS rol_orden,
  COALESCE(p.puede_ver, false)    AS puede_ver,
  COALESCE(p.puede_editar, false) AS puede_editar
FROM secciones_panel s
CROSS JOIN roles r
LEFT JOIN permisos_rol p ON p.seccion_id = s.id AND p.rol_id = r.id
ORDER BY s.orden, r.orden;

COMMENT ON VIEW vw_matriz_permisos IS 'Equivale a SECCIONES_PERMISOS de admin.html, con todas las combinaciones resueltas.';

COMMIT;
