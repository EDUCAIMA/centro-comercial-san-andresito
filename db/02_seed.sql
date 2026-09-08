-- ═══════════════════════════════════════════════════════════════════════════
--  DATOS INICIALES — Contenido real que hoy está escrito a mano en el HTML
--  Ejecutar después de 01_schema.sql:
--    psql "$DATABASE_URL" -f db/02_seed.sql
--
--  Es re-ejecutable: usa ON CONFLICT, así que correrlo dos veces actualiza
--  en lugar de duplicar. Las claves foráneas se resuelven por slug, nunca
--  por id fijo, para que el archivo no dependa del orden de inserción.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Datos del centro comercial ──────────────────────────────────────────
INSERT INTO configuracion_sitio (
  id, nombre, eslogan, descripcion,
  direccion, ciudad, departamento, pais, latitud, longitud,
  telefono, whatsapp, email,
  url_facebook, url_instagram, url_tiktok,
  horario_semana, horario_domingo
) VALUES (
  1,
  'Centro Comercial San Andresito del Eje',
  'El corazón comercial de Pereira',
  'Más de un centenar de comercios de moda, tecnología, hogar, belleza y gastronomía en el centro de Pereira.',
  'Cra. 8 entre Cll. 30 y 31', 'Pereira', 'Risaralda', 'CO',
  4.808700, -75.690600,
  '+5763350000', '+573000000000', 'contacto@sanandresitoeje.com',
  'https://facebook.com', 'https://instagram.com', 'https://tiktok.com',
  'Lunes a Sábado: 9:00 AM - 8:00 PM',
  'Domingos y Festivos: 10:00 AM - 6:00 PM'
)
ON CONFLICT (id) DO UPDATE SET
  nombre          = EXCLUDED.nombre,
  direccion       = EXCLUDED.direccion,
  telefono        = EXCLUDED.telefono,
  email           = EXCLUDED.email,
  horario_semana  = EXCLUDED.horario_semana,
  horario_domingo = EXCLUDED.horario_domingo,
  actualizado_en  = now();


-- ── 2. Categorías de comercio (vitrina "Categorías Destacadas") ────────────
INSERT INTO categorias (nombre, slug, icono, orden) VALUES
  ('Moda',         'moda',         'apparel',         1),
  ('Tecnología',   'tecnologia',   'devices',         2),
  ('Hogar',        'hogar',        'chair',           3),
  ('Belleza',      'belleza',      'spa',             4),
  ('Restaurantes', 'restaurantes', 'restaurant',      5),
  ('Servicios',    'servicios',    'account_balance', 6)
ON CONFLICT (slug) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  icono  = EXCLUDED.icono,
  orden  = EXCLUDED.orden;


-- ── 3. Pisos ───────────────────────────────────────────────────────────────
INSERT INTO pisos (numero, nombre, descripcion, orden) VALUES
  (1, 'Piso 1', 'Plaza Central, vitrinas principales y acceso por Carrera 8.', 1),
  (2, 'Piso 2', 'Moda, calzado y deportes.',                                   2),
  (3, 'Piso 3', 'Boulevard Gourmet, terraza y zona de comidas.',               3)
ON CONFLICT (numero) DO UPDATE SET
  nombre      = EXCLUDED.nombre,
  descripcion = EXCLUDED.descripcion;


-- ── 4. Locales ─────────────────────────────────────────────────────────────
INSERT INTO locales (codigo, piso_id, area_m2, estado)
SELECT v.codigo, p.id, v.area_m2, v.estado::estado_local
FROM (VALUES
  ('215', 2, 78.50, 'ocupado'),
  ('216', 2, 42.00, 'disponible'),
  ('101', 1, 65.00, 'disponible')
) AS v(codigo, piso_numero, area_m2, estado)
JOIN pisos p ON p.numero = v.piso_numero
ON CONFLICT (codigo) DO UPDATE SET
  piso_id = EXCLUDED.piso_id,
  area_m2 = EXCLUDED.area_m2,
  estado  = EXCLUDED.estado;


-- ── 5. Tiendas ─────────────────────────────────────────────────────────────
INSERT INTO tiendas (
  nombre, slug, descripcion, categoria_id, local_id,
  logo_url, whatsapp, activa, destacada, orden
)
SELECT
  'Nike Store',
  'nike-store',
  'Líderes en calzado deportivo, moda streetwear, líneas Jordan, running y accesorios de última colección con asesoría personalizada.',
  c.id,
  l.id,
  'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=200&q=80',
  '+573000000000',
  true, true, 1
FROM categorias c, locales l
WHERE c.slug = 'moda' AND l.codigo = '215'
ON CONFLICT (slug) DO UPDATE SET
  descripcion  = EXCLUDED.descripcion,
  categoria_id = EXCLUDED.categoria_id,
  local_id     = EXCLUDED.local_id,
  whatsapp     = EXCLUDED.whatsapp;


-- ── 6. Horario de Nike Store ───────────────────────────────────────────────
-- La ficha del sitio indica 09:30 - 20:00. El domingo se alinea al horario
-- general del centro comercial (10:00 - 18:00); ajústalo si la tienda difiere.
INSERT INTO horarios_tienda (tienda_id, dia_semana, hora_apertura, hora_cierre, cerrado)
SELECT t.id, v.dia, v.abre::time, v.cierra::time, false
FROM (VALUES
  (1, '09:30', '20:00'),   -- lunes
  (2, '09:30', '20:00'),   -- martes
  (3, '09:30', '20:00'),   -- miércoles
  (4, '09:30', '20:00'),   -- jueves
  (5, '09:30', '20:00'),   -- viernes
  (6, '09:30', '20:00'),   -- sábado
  (0, '10:00', '18:00')    -- domingo
) AS v(dia, abre, cierra)
CROSS JOIN tiendas t
WHERE t.slug = 'nike-store'
ON CONFLICT (tienda_id, dia_semana) DO UPDATE SET
  hora_apertura = EXCLUDED.hora_apertura,
  hora_cierre   = EXCLUDED.hora_cierre,
  cerrado       = EXCLUDED.cerrado;


-- ── 7. Categorías de producto (filtro lateral del catálogo) ────────────────
INSERT INTO categorias_producto (nombre, slug, orden) VALUES
  ('Zapatillas Urbanas', 'zapatillas', 1),
  ('Running',            'running',    2),
  ('Ropa y Textil',      'ropa',       3)
ON CONFLICT (slug) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  orden  = EXCLUDED.orden;


-- ── 8. Catálogo de Nike Store ──────────────────────────────────────────────
INSERT INTO productos (
  tienda_id, categoria_producto_id, nombre, slug, descripcion, linea,
  precio, imagen_url, etiqueta, disponibilidad, nota_disponibilidad,
  destacado, orden
)
SELECT
  t.id, cp.id, v.nombre, v.slug, v.descripcion, v.linea,
  v.precio, v.imagen_url, v.etiqueta,
  v.disponibilidad::disponibilidad_producto, v.nota,
  v.destacado, v.orden
FROM (VALUES
  ('Nike Air Max Pulse Red',    'nike-air-max-pulse-red',
   'Amortiguación reactiva con cámara de aire visible y diseño aerodinámico.',
   'Calzado Hombre',      589900.00,
   'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=600&q=80',
   'Nuevo',      'disponible',       NULL,                  true,  1, 'zapatillas'),

  ('Air Jordan 1 Retro High',   'air-jordan-1-retro-high',
   'El clásico del baloncesto con materiales premium y acabados exclusivos.',
   'Línea Urbana',        690000.00,
   'https://images.unsplash.com/photo-1552346154-21d32810aba3?auto=format&fit=crop&w=600&q=80',
   'Jordan',     'ultimas_unidades', 'Últimos pares',       true,  2, 'zapatillas'),

  ('Nike Air Zoom Pegasus',     'nike-air-zoom-pegasus',
   'Máxima ligereza para entrenamientos diarios y carreras de larga distancia.',
   'Running Profesional', 489900.00,
   'https://images.unsplash.com/photo-1608231387042-66d1773070a5?auto=format&fit=crop&w=600&q=80',
   'Top Ventas', 'disponible',       NULL,                  true,  3, 'running'),

  ('Chaqueta Nike Windrunner',  'chaqueta-nike-windrunner',
   'Tejido repelente al agua, capucha ajustable y corte clásico chevron.',
   'Textil & Ropa',       320000.00,
   'https://images.unsplash.com/photo-1556905055-8f358a7a47b2?auto=format&fit=crop&w=600&q=80',
   NULL,         'disponible',       'Tallas S, M, L, XL',  false, 4, 'ropa')
) AS v(nombre, slug, descripcion, linea, precio, imagen_url, etiqueta,
       disponibilidad, nota, destacado, orden, categoria_slug)
CROSS JOIN tiendas t
JOIN categorias_producto cp ON cp.slug = v.categoria_slug
WHERE t.slug = 'nike-store'
ON CONFLICT (tienda_id, slug) DO UPDATE SET
  nombre                = EXCLUDED.nombre,
  descripcion           = EXCLUDED.descripcion,
  linea                 = EXCLUDED.linea,
  precio                = EXCLUDED.precio,
  imagen_url            = EXCLUDED.imagen_url,
  etiqueta              = EXCLUDED.etiqueta,
  disponibilidad        = EXCLUDED.disponibilidad,
  nota_disponibilidad   = EXCLUDED.nota_disponibilidad,
  categoria_producto_id = EXCLUDED.categoria_producto_id;


-- ── 9. Categorías de evento ────────────────────────────────────────────────
-- 'clases_css' replica el mapa CATEGORIAS del carrusel en inicio.html.
INSERT INTO categorias_evento (nombre, slug, etiqueta, clases_css, orden) VALUES
  ('Tecnología',  'tecnologia',  'Tecnología',         'bg-[#D97C2B] text-white',    1),
  ('Gastronomía', 'gastronomia', 'Gastronomía & Show', 'bg-[#D99923] text-[#0D0D0D]', 2),
  ('Moda',        'moda',        'Moda & Calzado',     'bg-[#D97C2B] text-white',    3),
  ('Familiar',    'familiar',    'Familiar & Niños',   'bg-[#D99923] text-[#0D0D0D]', 4)
ON CONFLICT (slug) DO UPDATE SET
  etiqueta   = EXCLUDED.etiqueta,
  clases_css = EXCLUDED.clases_css;


-- ── 10. Agenda de eventos ──────────────────────────────────────────────────
-- Las marcas de tiempo llevan el desfase -05:00 de Colombia de forma
-- explícita, para que la fecha no cambie según la zona del servidor.
INSERT INTO eventos (
  titulo, slug, descripcion, categoria_evento_id,
  inicio, fin, lugar, entrada, imagen_url, activo, destacado
)
SELECT
  v.titulo, v.slug, v.descripcion, ce.id,
  v.inicio::timestamptz, v.fin::timestamptz,
  v.lugar, v.entrada, v.imagen_url, true, v.destacado
FROM (VALUES
  ('Expo Tech & Gadgets 2026', 'expo-tech-gadgets-2026',
   'Lanzamientos en telefonía, accesorios gamer, descuentos exclusivos de temporada y sorteos en vivo.',
   '2026-10-12 14:00:00-05', '2026-10-12 19:00:00-05',
   'Plaza Central • Piso 1', 'Entrada libre',
   'https://images.unsplash.com/photo-1519389950473-47ba0277781c?auto=format&fit=crop&w=1200&q=80',
   true, 'tecnologia'),

  ('Atardecer Cafetero & Acústico', 'atardecer-cafetero-acustico',
   'Catas de café especial del Eje, repostería artesanal y música en vivo con artistas locales de Pereira.',
   '2026-10-18 17:30:00-05', '2026-10-18 21:00:00-05',
   'Terraza Boulevard Gourmet', 'Entrada libre',
   'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=1200&q=80',
   false, 'gastronomia'),

  ('Gran Trasnochón San Andresito', 'gran-trasnochon-san-andresito',
   'Hasta 50% de descuento en calzado, perfumería y moda con horario extendido hasta las 11:00 PM.',
   '2026-11-01 10:00:00-05', '2026-11-01 23:00:00-05',
   'Todos los niveles del Mall', 'Entrada libre',
   'https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=1200&q=80',
   true, 'moda'),

  ('Festival de la Familia & Arte Infantil', 'festival-familia-arte-infantil',
   'Talleres recreativos, show de magia y sorpresas para compartir en familia en el centro de Pereira.',
   '2026-11-15 11:00:00-05', '2026-11-15 17:00:00-05',
   'Plazoleta Principal', 'Entrada libre',
   'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=1200&q=80',
   false, 'familiar')
) AS v(titulo, slug, descripcion, inicio, fin, lugar, entrada,
       imagen_url, destacado, categoria_slug)
JOIN categorias_evento ce ON ce.slug = v.categoria_slug
ON CONFLICT (slug) DO UPDATE SET
  titulo              = EXCLUDED.titulo,
  descripcion         = EXCLUDED.descripcion,
  inicio              = EXCLUDED.inicio,
  fin                 = EXCLUDED.fin,
  lugar               = EXCLUDED.lugar,
  imagen_url          = EXCLUDED.imagen_url,
  categoria_evento_id = EXCLUDED.categoria_evento_id;

COMMIT;


-- ── Comprobación rápida de lo cargado ──────────────────────────────────────
SELECT 'configuracion_sitio'  AS tabla, count(*) FROM configuracion_sitio
UNION ALL SELECT 'categorias',          count(*) FROM categorias
UNION ALL SELECT 'pisos',               count(*) FROM pisos
UNION ALL SELECT 'locales',             count(*) FROM locales
UNION ALL SELECT 'tiendas',             count(*) FROM tiendas
UNION ALL SELECT 'horarios_tienda',     count(*) FROM horarios_tienda
UNION ALL SELECT 'categorias_producto', count(*) FROM categorias_producto
UNION ALL SELECT 'productos',           count(*) FROM productos
UNION ALL SELECT 'categorias_evento',   count(*) FROM categorias_evento
UNION ALL SELECT 'eventos',             count(*) FROM eventos;
