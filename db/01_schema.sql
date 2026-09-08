-- ═══════════════════════════════════════════════════════════════════════════
--  CENTRO COMERCIAL SAN ANDRESITO DEL EJE — Esquema de base de datos
--  Motor : PostgreSQL 14+   ·   Despliegue: Railway
--  Zona horaria del negocio: America/Bogota (UTC-5, sin horario de verano)
--
--  Este archivo es idempotente: puede ejecutarse varias veces sin romper nada.
--    psql "$DATABASE_URL" -f db/01_schema.sql
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Extensiones ────────────────────────────────────────────────────────────
-- pg_trgm habilita la búsqueda por nombre tolerante a errores de escritura
-- ("nike ar max" encuentra "Nike Air Max").
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ── Tipos enumerados ───────────────────────────────────────────────────────
-- Envueltos en bloques DO porque PostgreSQL no admite CREATE TYPE IF NOT EXISTS.
DO $$ BEGIN
  CREATE TYPE estado_local AS ENUM ('disponible', 'ocupado', 'reservado', 'mantenimiento');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE disponibilidad_producto AS ENUM ('disponible', 'ultimas_unidades', 'agotado', 'bajo_pedido');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── Función de apoyo: mantiene actualizado_en al día ───────────────────────
CREATE OR REPLACE FUNCTION fn_marcar_actualizacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.actualizado_en := now();
  RETURN NEW;
END;
$$;

-- Los slugs se usan en las URLs: minúsculas, números y guiones simples.
-- Ejemplos válidos: 'nike-store', 'moda', 'expo-tech-gadgets-2026'
CREATE OR REPLACE FUNCTION fn_slug_valido(texto text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$ SELECT texto ~ '^[a-z0-9]+(-[a-z0-9]+)*$' $$;


-- ═══════════════════════════════════════════════════════════════════════════
--  1. CONFIGURACIÓN DEL SITIO
--     Tabla de una sola fila: los datos del centro comercial que aparecen
--     en la cabecera, el pie de página y el mapa. El CHECK sobre id impide
--     que se creen filas adicionales por error.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS configuracion_sitio (
  id                 smallint     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  nombre             varchar(120) NOT NULL,
  eslogan            varchar(200),
  descripcion        text,

  -- Ubicación física
  direccion          varchar(200) NOT NULL,
  ciudad             varchar(80)  NOT NULL DEFAULT 'Pereira',
  departamento       varchar(80)  NOT NULL DEFAULT 'Risaralda',
  pais               char(2)      NOT NULL DEFAULT 'CO',
  latitud            numeric(9,6),
  longitud           numeric(9,6),

  -- Contacto
  telefono           varchar(25),
  whatsapp           varchar(25),
  email              varchar(150) CHECK (email IS NULL OR email LIKE '%_@_%._%'),

  -- Redes sociales
  url_facebook       text,
  url_instagram      text,
  url_tiktok         text,

  -- Horario general del centro comercial (el de cada tienda va en su tabla)
  horario_semana     varchar(60),
  horario_domingo    varchar(60),

  actualizado_en     timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE configuracion_sitio IS 'Datos generales del centro comercial. Siempre una única fila (id = 1).';


-- ═══════════════════════════════════════════════════════════════════════════
--  2. CATEGORÍAS DE COMERCIO
--     Moda, Tecnología, Hogar, Belleza, Restaurantes, Servicios.
--     'icono' guarda el nombre del Material Symbol que ya usa el HTML.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS categorias (
  id             int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre         varchar(80)  NOT NULL UNIQUE,
  slug           varchar(90)  NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  descripcion    text,
  icono          varchar(60),
  imagen_url     text,
  orden          smallint     NOT NULL DEFAULT 0,
  activa         boolean      NOT NULL DEFAULT true,
  creado_en      timestamptz  NOT NULL DEFAULT now(),
  actualizado_en timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON COLUMN categorias.icono IS 'Nombre del Material Symbol usado en el sitio (apparel, devices, chair…).';
COMMENT ON COLUMN categorias.orden  IS 'Posición en la vitrina de categorías destacadas. Menor número aparece primero.';


-- ═══════════════════════════════════════════════════════════════════════════
--  3. PISOS Y LOCALES
--     Un local pertenece a un piso y aloja como máximo una tienda activa.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pisos (
  id          int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  numero      smallint     NOT NULL UNIQUE,
  nombre      varchar(80)  NOT NULL,
  descripcion text,
  orden       smallint     NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS locales (
  id          int           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      varchar(20)   NOT NULL UNIQUE,
  piso_id     int           NOT NULL REFERENCES pisos(id) ON DELETE RESTRICT,
  area_m2     numeric(8,2)  CHECK (area_m2 IS NULL OR area_m2 > 0),
  estado      estado_local  NOT NULL DEFAULT 'disponible',
  notas       text,
  creado_en   timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_locales_piso   ON locales (piso_id);
CREATE INDEX IF NOT EXISTS ix_locales_estado ON locales (estado);

COMMENT ON COLUMN locales.codigo IS 'Número visible del local, como aparece en la señalización: 215, 101-A…';


-- ═══════════════════════════════════════════════════════════════════════════
--  4. TIENDAS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS tiendas (
  id             int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre         varchar(120) NOT NULL,
  slug           varchar(140) NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  descripcion    text,

  categoria_id   int          NOT NULL REFERENCES categorias(id) ON DELETE RESTRICT,
  local_id       int          REFERENCES locales(id) ON DELETE SET NULL,

  logo_url       text,
  portada_url    text,

  -- Contacto propio de la tienda
  telefono       varchar(25),
  whatsapp       varchar(25),
  email          varchar(150) CHECK (email IS NULL OR email LIKE '%_@_%._%'),
  sitio_web      text,
  url_instagram  text,
  url_facebook   text,

  activa         boolean      NOT NULL DEFAULT true,
  destacada      boolean      NOT NULL DEFAULT false,
  orden          smallint     NOT NULL DEFAULT 0,

  creado_en      timestamptz  NOT NULL DEFAULT now(),
  actualizado_en timestamptz  NOT NULL DEFAULT now(),

  -- Índice de búsqueda: se recalcula solo cuando cambian nombre o descripción
  busqueda tsvector GENERATED ALWAYS AS (
    to_tsvector('spanish', coalesce(nombre, '') || ' ' || coalesce(descripcion, ''))
  ) STORED
);

-- Un local no puede tener dos tiendas activas al mismo tiempo, pero sí
-- conservar el histórico de las que estuvieron antes (activa = false).
CREATE UNIQUE INDEX IF NOT EXISTS ux_tiendas_local_activo
  ON tiendas (local_id) WHERE activa AND local_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_tiendas_categoria ON tiendas (categoria_id);
CREATE INDEX IF NOT EXISTS ix_tiendas_activas   ON tiendas (activa) WHERE activa;
CREATE INDEX IF NOT EXISTS ix_tiendas_busqueda  ON tiendas USING gin (busqueda);
CREATE INDEX IF NOT EXISTS ix_tiendas_nombre_trgm ON tiendas USING gin (nombre gin_trgm_ops);

DROP TRIGGER IF EXISTS tg_tiendas_actualizacion ON tiendas;
CREATE TRIGGER tg_tiendas_actualizacion
  BEFORE UPDATE ON tiendas
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();


-- ═══════════════════════════════════════════════════════════════════════════
--  5. HORARIOS DE ATENCIÓN
--     Una fila por día de la semana y tienda. Permite calcular el distintivo
--     "Abierto ahora" que muestra la ficha de tienda.
--     dia_semana sigue la convención de JavaScript y de EXTRACT(DOW): 0 = domingo.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS horarios_tienda (
  id             int      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tienda_id      int      NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
  dia_semana     smallint NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
  hora_apertura  time,
  hora_cierre    time,
  cerrado        boolean  NOT NULL DEFAULT false,

  UNIQUE (tienda_id, dia_semana),

  -- Si el día está abierto exige ambas horas y que cierre después de abrir.
  CONSTRAINT ck_horario_coherente CHECK (
    (cerrado AND hora_apertura IS NULL AND hora_cierre IS NULL)
    OR (NOT cerrado AND hora_apertura IS NOT NULL AND hora_cierre IS NOT NULL
        AND hora_cierre > hora_apertura)
  )
);

CREATE INDEX IF NOT EXISTS ix_horarios_tienda ON horarios_tienda (tienda_id);


-- ═══════════════════════════════════════════════════════════════════════════
--  6. CATEGORÍAS DE PRODUCTO
--     Alimentan el filtro lateral del catálogo (zapatillas, running, ropa…).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS categorias_producto (
  id        int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre    varchar(80)  NOT NULL,
  slug      varchar(90)  NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  orden     smallint     NOT NULL DEFAULT 0,
  activa    boolean      NOT NULL DEFAULT true
);

COMMENT ON COLUMN categorias_producto.slug IS 'Coincide con el atributo data-cat de las tarjetas en tienda.html.';


-- ═══════════════════════════════════════════════════════════════════════════
--  7. PRODUCTOS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS productos (
  id                    int           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tienda_id             int           NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
  categoria_producto_id int           REFERENCES categorias_producto(id) ON DELETE SET NULL,

  nombre                varchar(160)  NOT NULL,
  slug                  varchar(180)  NOT NULL CHECK (fn_slug_valido(slug)),
  descripcion           text,
  linea                 varchar(60),

  -- Precios en pesos colombianos. numeric evita los errores de redondeo
  -- que tendría un tipo de punto flotante con cifras de seis dígitos.
  precio                numeric(12,2) NOT NULL CHECK (precio >= 0),
  precio_anterior       numeric(12,2) CHECK (precio_anterior IS NULL OR precio_anterior > precio),
  moneda                char(3)       NOT NULL DEFAULT 'COP',

  imagen_url            text,
  etiqueta              varchar(30),
  disponibilidad        disponibilidad_producto NOT NULL DEFAULT 'disponible',
  nota_disponibilidad   varchar(80),

  destacado             boolean       NOT NULL DEFAULT false,
  activo                boolean       NOT NULL DEFAULT true,
  orden                 smallint      NOT NULL DEFAULT 0,

  creado_en             timestamptz   NOT NULL DEFAULT now(),
  actualizado_en        timestamptz   NOT NULL DEFAULT now(),

  busqueda tsvector GENERATED ALWAYS AS (
    to_tsvector('spanish', coalesce(nombre, '') || ' ' || coalesce(descripcion, '') || ' ' || coalesce(linea, ''))
  ) STORED,

  -- El slug identifica al producto dentro de su tienda, no en todo el sitio:
  -- dos tiendas pueden vender una "chaqueta-negra" sin chocar entre sí.
  UNIQUE (tienda_id, slug)
);

CREATE INDEX IF NOT EXISTS ix_productos_tienda    ON productos (tienda_id);
CREATE INDEX IF NOT EXISTS ix_productos_categoria ON productos (categoria_producto_id);
CREATE INDEX IF NOT EXISTS ix_productos_activos   ON productos (activo) WHERE activo;
CREATE INDEX IF NOT EXISTS ix_productos_precio    ON productos (precio) WHERE activo;
CREATE INDEX IF NOT EXISTS ix_productos_busqueda  ON productos USING gin (busqueda);
CREATE INDEX IF NOT EXISTS ix_productos_nombre_trgm ON productos USING gin (nombre gin_trgm_ops);

DROP TRIGGER IF EXISTS tg_productos_actualizacion ON productos;
CREATE TRIGGER tg_productos_actualizacion
  BEFORE UPDATE ON productos
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();

COMMENT ON COLUMN productos.linea     IS 'Subtítulo comercial mostrado sobre el nombre: "Calzado Hombre", "Running Profesional".';
COMMENT ON COLUMN productos.etiqueta  IS 'Distintivo sobre la foto: Nuevo, Top Ventas, Jordan… NULL si no lleva.';


-- ═══════════════════════════════════════════════════════════════════════════
--  8. EVENTOS
--     Alimenta el carrusel "Próximos Eventos" de inicio.html. Las columnas
--     reproducen exactamente los campos del array EVENTOS de esa página.
--     El día de la semana NO se guarda: se deriva de 'inicio', para que
--     fecha y día jamás puedan contradecirse.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS categorias_evento (
  id           int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre       varchar(60)  NOT NULL UNIQUE,
  slug         varchar(70)  NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  etiqueta     varchar(60)  NOT NULL,
  clases_css   varchar(120) NOT NULL DEFAULT 'bg-[#D97C2B] text-white',
  orden        smallint     NOT NULL DEFAULT 0
);

COMMENT ON COLUMN categorias_evento.etiqueta   IS 'Texto que se pinta en el distintivo de la tarjeta.';
COMMENT ON COLUMN categorias_evento.clases_css IS 'Clases Tailwind del distintivo, según el mapa CATEGORIAS de inicio.html.';

CREATE TABLE IF NOT EXISTS eventos (
  id                   int          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  titulo               varchar(160) NOT NULL,
  slug                 varchar(180) NOT NULL UNIQUE CHECK (fn_slug_valido(slug)),
  descripcion          text,

  categoria_evento_id  int          REFERENCES categorias_evento(id) ON DELETE SET NULL,

  -- timestamptz: se guarda el instante exacto, sin ambigüedad de zona horaria.
  inicio               timestamptz  NOT NULL,
  fin                  timestamptz  NOT NULL,

  lugar                varchar(160),
  entrada              varchar(60)  DEFAULT 'Entrada libre',
  imagen_url           text,

  activo               boolean      NOT NULL DEFAULT true,
  destacado            boolean      NOT NULL DEFAULT false,

  creado_en            timestamptz  NOT NULL DEFAULT now(),
  actualizado_en       timestamptz  NOT NULL DEFAULT now(),

  CONSTRAINT ck_evento_rango CHECK (fin > inicio)
);

CREATE INDEX IF NOT EXISTS ix_eventos_inicio    ON eventos (inicio);
CREATE INDEX IF NOT EXISTS ix_eventos_proximos  ON eventos (fin) WHERE activo;
CREATE INDEX IF NOT EXISTS ix_eventos_categoria ON eventos (categoria_evento_id);

DROP TRIGGER IF EXISTS tg_eventos_actualizacion ON eventos;
CREATE TRIGGER tg_eventos_actualizacion
  BEFORE UPDATE ON eventos
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_actualizacion();


-- ═══════════════════════════════════════════════════════════════════════════
--  9. VISTAS
--     Resuelven en la base de datos dos preguntas que el sitio hace siempre.
-- ═══════════════════════════════════════════════════════════════════════════

-- Eventos que aún no terminan, en el mismo orden que muestra el carrusel.
CREATE OR REPLACE VIEW vw_proximos_eventos AS
SELECT
  e.id,
  e.titulo,
  e.slug,
  e.descripcion,
  e.inicio,
  e.fin,
  e.lugar,
  e.entrada,
  e.imagen_url,
  ce.nombre     AS categoria,
  ce.etiqueta   AS categoria_etiqueta,
  ce.clases_css AS categoria_clases,
  -- Días completos que faltan, ya en hora de Colombia
  (e.inicio AT TIME ZONE 'America/Bogota')::date
    - (now() AT TIME ZONE 'America/Bogota')::date AS dias_faltantes
FROM eventos e
LEFT JOIN categorias_evento ce ON ce.id = e.categoria_evento_id
WHERE e.activo
  AND e.fin >= now()
ORDER BY e.inicio;

COMMENT ON VIEW vw_proximos_eventos IS 'Agenda vigente para el carrusel de inicio.html. Descarta los eventos ya terminados.';


-- Tiendas que están atendiendo en este momento, según la hora de Pereira.
CREATE OR REPLACE VIEW vw_tiendas_abiertas AS
SELECT
  t.id,
  t.nombre,
  t.slug,
  t.logo_url,
  c.nombre        AS categoria,
  l.codigo        AS local,
  p.numero        AS piso,
  h.hora_apertura,
  h.hora_cierre
FROM tiendas t
JOIN horarios_tienda h ON h.tienda_id = t.id
JOIN categorias c      ON c.id = t.categoria_id
LEFT JOIN locales l    ON l.id = t.local_id
LEFT JOIN pisos p      ON p.id = l.piso_id
WHERE t.activa
  AND NOT h.cerrado
  AND h.dia_semana = EXTRACT(DOW FROM (now() AT TIME ZONE 'America/Bogota'))::smallint
  AND (now() AT TIME ZONE 'America/Bogota')::time BETWEEN h.hora_apertura AND h.hora_cierre;

COMMENT ON VIEW vw_tiendas_abiertas IS 'Alimenta el distintivo "Abierto ahora". Se evalúa en hora de Colombia, no en UTC.';

COMMIT;
