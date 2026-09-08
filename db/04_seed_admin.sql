-- ═══════════════════════════════════════════════════════════════════════════
--  DATOS INICIALES DE LA CAPA ADMINISTRATIVA
--  Ejecutar después de 03_admin.sql:
--    psql "$DATABASE_URL" -f db/04_seed_admin.sql
--
--  Roles, secciones y matriz de permisos son estructura del panel, no datos
--  de ejemplo: el sistema los necesita para funcionar. Los usuarios y las
--  diapositivas sí provienen del contenido actual de admin.html.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Roles ──────────────────────────────────────────────────────────────────
INSERT INTO roles (nombre, slug, descripcion, clase_chip, es_sistema, orden) VALUES
  ('Super Administrador', 'super-administrador', 'Control total del panel, incluidos usuarios y ajustes del sitio.', 'chip-primary', true,  1),
  ('Editor',              'editor',              'Edita todo el contenido publicado, sin acceso a usuarios ni ajustes.', 'chip-gold',   true,  2),
  ('Gestor de comercios', 'gestor-comercios',    'Mantiene el directorio de comercios y sus categorías.',                'chip-off',    false, 3),
  ('Gestor de eventos',   'gestor-eventos',      'Mantiene la agenda de eventos.',                                      'chip-off',    false, 4)
ON CONFLICT (slug) DO UPDATE SET
  nombre      = EXCLUDED.nombre,
  descripcion = EXCLUDED.descripcion,
  clase_chip  = EXCLUDED.clase_chip;


-- ── Secciones del panel ────────────────────────────────────────────────────
INSERT INTO secciones_panel (nombre, slug, icono, orden) VALUES
  ('Hero / Carrusel',      'hero',       'view_carousel',  1),
  ('Comercios',            'comercios',  'storefront',     2),
  ('Categorías',           'categorias', 'category',       3),
  ('Eventos',              'eventos',    'event',          4),
  ('Galería de imágenes',  'galeria',    'photo_library',  5),
  ('Ubicación y horarios', 'ubicacion',  'location_on',    6),
  ('Textos y footer',      'contenido',  'article',        7),
  ('Usuarios',             'usuarios',   'group',          8),
  ('Ajustes del sitio',    'ajustes',    'settings',       9)
ON CONFLICT (slug) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  icono  = EXCLUDED.icono,
  orden  = EXCLUDED.orden;


-- ── Matriz de permisos ─────────────────────────────────────────────────────
-- Reproduce SECCIONES_PERMISOS de admin.html. Cada columna es un rol, en el
-- mismo orden: Super Administrador, Editor, Gestor de comercios, Gestor de eventos.
INSERT INTO permisos_rol (rol_id, seccion_id, puede_ver, puede_editar)
SELECT r.id, s.id, v.permitido, v.permitido
FROM (VALUES
  ('hero',       'super-administrador', true ), ('hero',       'editor', true ), ('hero',       'gestor-comercios', false), ('hero',       'gestor-eventos', false),
  ('comercios',  'super-administrador', true ), ('comercios',  'editor', true ), ('comercios',  'gestor-comercios', true ), ('comercios',  'gestor-eventos', false),
  ('categorias', 'super-administrador', true ), ('categorias', 'editor', true ), ('categorias', 'gestor-comercios', true ), ('categorias', 'gestor-eventos', false),
  ('eventos',    'super-administrador', true ), ('eventos',    'editor', true ), ('eventos',    'gestor-comercios', false), ('eventos',    'gestor-eventos', true ),
  ('galeria',    'super-administrador', true ), ('galeria',    'editor', true ), ('galeria',    'gestor-comercios', true ), ('galeria',    'gestor-eventos', true ),
  ('ubicacion',  'super-administrador', true ), ('ubicacion',  'editor', true ), ('ubicacion',  'gestor-comercios', false), ('ubicacion',  'gestor-eventos', false),
  ('contenido',  'super-administrador', true ), ('contenido',  'editor', true ), ('contenido',  'gestor-comercios', false), ('contenido',  'gestor-eventos', false),
  ('usuarios',   'super-administrador', true ), ('usuarios',   'editor', false), ('usuarios',   'gestor-comercios', false), ('usuarios',   'gestor-eventos', false),
  ('ajustes',    'super-administrador', true ), ('ajustes',    'editor', false), ('ajustes',    'gestor-comercios', false), ('ajustes',    'gestor-eventos', false)
) AS v(seccion_slug, rol_slug, permitido)
JOIN secciones_panel s ON s.slug = v.seccion_slug
JOIN roles r           ON r.slug = v.rol_slug
ON CONFLICT (rol_id, seccion_id) DO UPDATE SET
  puede_ver    = EXCLUDED.puede_ver,
  puede_editar = EXCLUDED.puede_editar;


-- ── Usuarios del panel ─────────────────────────────────────────────────────
-- Se crean en estado 'invitado' y SIN contraseña a propósito: cada persona
-- define la suya al aceptar la invitación. La aplicación debe guardar ahí el
-- hash de bcrypt o argon2 y cambiar el estado a 'activo'.
INSERT INTO usuarios_admin (nombre, email, rol_id, estado)
SELECT v.nombre, v.email, r.id, 'invitado'::estado_usuario
FROM (VALUES
  ('Eduardo Caicedo', 'eduardo.caicedom@gmail.com',       'super-administrador'),
  ('Marcela Ríos',    'marcela.rios@sanandresitoeje.com', 'editor'),
  ('Julián Vélez',    'julian.velez@sanandresitoeje.com', 'gestor-comercios'),
  ('Laura Ospina',    'laura.ospina@sanandresitoeje.com', 'gestor-eventos')
) AS v(nombre, email, rol_slug)
JOIN roles r ON r.slug = v.rol_slug
ON CONFLICT (email) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  rol_id = EXCLUDED.rol_id;


-- ── Ajustes del sitio ──────────────────────────────────────────────────────
INSERT INTO ajustes_sitio (clave, valor, grupo, etiqueta, tipo) VALUES
  ('seo.titulo',            'San Andresito del Eje - Centro Comercial',                    'seo',      'Título de la página',        'texto'),
  ('seo.descripcion',       'Directorio de comercios, agenda de eventos y catálogo del Centro Comercial San Andresito del Eje en Pereira.', 'seo', 'Descripción para buscadores', 'texto_largo'),
  ('seo.imagen_compartir',  '',                                                            'seo',      'Imagen al compartir en redes', 'url'),

  ('hero.intervalo_ms',     '6000',                                                        'hero',     'Tiempo entre diapositivas (ms)', 'numero'),

  ('barra.mostrar',         'true',                                                        'barra',    'Mostrar barra superior',     'booleano'),
  ('barra.mensaje',         'Cra. 8 entre Cll. 30 y 31, Pereira',                          'barra',    'Mensaje de la barra superior','texto'),

  ('footer.descripcion',    'El corazón comercial de Pereira: moda, tecnología, hogar, belleza y gastronomía en un solo lugar.', 'footer', 'Texto del pie de página', 'texto_largo'),
  ('footer.derechos',       '© 2026 Centro Comercial San Andresito del Eje. Todos los derechos reservados.', 'footer', 'Aviso de derechos', 'texto'),

  ('marca.color_primario',  '#D97C2B',                                                     'identidad','Color primario',             'color'),
  ('marca.color_secundario','#D99923',                                                     'identidad','Color secundario',           'color'),
  ('marca.logo_url',        '',                                                            'identidad','Logotipo',                   'url'),

  ('sitio.mantenimiento',   'false',                                                       'general',  'Modo mantenimiento',         'booleano')
ON CONFLICT (clave) DO UPDATE SET
  grupo    = EXCLUDED.grupo,
  etiqueta = EXCLUDED.etiqueta,
  tipo     = EXCLUDED.tipo;


-- ── Diapositivas del hero ──────────────────────────────────────────────────
INSERT INTO hero_slides (titulo, descripcion, imagen_url, icono, texto_boton, enlace, activo, orden) VALUES
  ('San Andresito del Eje', 'Todo lo que buscas en un solo lugar: moda, tecnología, gastronomía y los mejores precios de la región.',
   'https://lh3.googleusercontent.com/aida-public/AB6AXuCg0QBksIf-t60frWJd-nO8ciWMsJQ1pz7wMKrQhgo9q-hCD1yecv09gcDtEvXVXt9e1_Gc525lw2R5wWGPhBzoImI5AJ82vTfaVVsyWjz4zX4079I5mlL_9AIAFIKLVOuDWMP3gasoPRWIF0DZTDB1Y-hAigK1sMid0YcfYXPGPUqrsVdggYN5H4d7pKZBwqCZak4c8_vfINcOV53BJX_KIj6fIOz5jJqMmQJMyoBjZtEwTzTC10p4Gg2IX-Sz8Aoc4pc',
   'storefront', 'Explorar Locales', '#tiendas', true, 1),
  ('Gran Variedad y Calidad', 'Las mejores marcas en calzado, perfumería, electrónica y moda con atención cercana y personalizada.',
   'https://lh3.googleusercontent.com/aida-public/AB6AXuBmWAb4GYZWhwhS2L4d_ZmpVxxvWHh595f0MB8E0Vpz25GKf6tZDOQzztAm7-DkLHsJtFBtMxJRiRXjCsKLZH08Fn4VcZJIM-HzFavlm3_s5-jHDT93tymZheTuZLT_VU0JsLpDOU4YEhdyoZevsPzWKGI2559HeaPyv5m0veQFvbCGVVY0oHAn2GODLSbN-Q8Zy2At9aIfsd6s-gSmVGFtQmwnqSUnRZHoVbPFZnVZdMU9h_STjORVnA',
   'storefront', 'Explorar Comercios', '#tiendas', true, 2),
  ('Momentos para Compartir', 'Disfruta de nuestra zona gourmet, terrazas al aire libre y la mejor selección de café del Eje Cafetero.',
   'https://lh3.googleusercontent.com/aida-public/AB6AXuCuItd6EXWnzKT569V-3mEn-MJtDNPcbb4y-lhwCIm8ROZDq_3Pa1SWzox1_lpqPX8gstUw0oCpr1Gg7dsb_OxvdS_o19nI0a3kQYOzoCh4hxs5CWSRp2rxy2HPCnjO35CtCkSj0ENNwtziKLaOAOqcCkEBdiYVue2DwNtI0AolSRbr_ocwJaQIjT26KfeNuVe___ulQW-o4-BhcWgBUvQjT5qQaqBDVZYu9U3HpKb5-oD0t66kA23PNg',
   'dinner_dining', 'Ver Restaurantes', '#tiendas', true, 3)
ON CONFLICT (titulo) DO UPDATE SET
  descripcion = EXCLUDED.descripcion,
  imagen_url  = EXCLUDED.imagen_url,
  icono       = EXCLUDED.icono,
  texto_boton = EXCLUDED.texto_boton,
  enlace      = EXCLUDED.enlace,
  orden       = EXCLUDED.orden;

COMMIT;
