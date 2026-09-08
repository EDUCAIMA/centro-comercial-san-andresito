# Base de datos — Centro Comercial San Andresito del Eje

PostgreSQL 14 o superior. Probado sobre PostgreSQL 18.

| Archivo | Qué contiene |
|---|---|
| `01_schema.sql` | Tablas, tipos, restricciones, índices, triggers y vistas |
| `02_seed.sql` | El contenido real que hoy está escrito a mano en `inicio.html` y `tienda.html` |

Ambos son **idempotentes**: se pueden ejecutar varias veces sin duplicar datos ni fallar.

---

## Cargar en Railway

**1. Crear la base.** En tu proyecto de Railway: `New` → `Database` → `Add PostgreSQL`.

**2. Obtener la cadena de conexión.** En el servicio Postgres, pestaña `Variables`, copia
`DATABASE_PUBLIC_URL` (la que termina en `.proxy.rlwy.net`). La variable `DATABASE_URL`
solo funciona desde dentro de la red de Railway.

**3. Cargar los archivos** desde tu equipo, en este orden:

```bash
export DATABASE_URL="postgresql://postgres:...@...proxy.rlwy.net:PUERTO/railway"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/01_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/02_seed.sql
```

`ON_ERROR_STOP=1` detiene la carga ante el primer error en lugar de dejar la base a medias.

Si prefieres la CLI de Railway, `railway connect postgres` abre `psql` ya conectado y
allí puedes usar `\i db/01_schema.sql`.

---

## Modelo de datos

```
configuracion_sitio          Datos del centro comercial (una sola fila)

categorias ──┐
             ├──> tiendas ──┬──> horarios_tienda   (uno por día de la semana)
pisos ──> locales ──────────┘   └──> productos ──> categorias_producto

categorias_evento ──> eventos
```

**Vistas incluidas**

- `vw_proximos_eventos` — eventos vigentes ordenados por fecha, con los días que faltan.
  Descarta solo los que ya terminaron, igual que el carrusel de `inicio.html`.
- `vw_tiendas_abiertas` — tiendas atendiendo en este momento, evaluado en hora de Pereira.

---

## Detalles que conviene conocer

**Zona horaria.** Todas las marcas de tiempo son `timestamptz` y la semilla las graba con
el desfase `-05:00` explícito. Colombia no tiene horario de verano, así que la hora es
estable todo el año. Las vistas convierten a `America/Bogota` antes de comparar, de modo
que "abierto ahora" responde a la hora local y no a la UTC del servidor.

**El día de la semana no se guarda.** Se deriva de la fecha del evento. Es a propósito:
en el HTML original el día escrito a mano no coincidía con la fecha en 3 de los 4 eventos.

**Precios.** `numeric(12,2)`, nunca `float`. Con cifras de seis dígitos en pesos, un tipo
de punto flotante introduce errores de redondeo.

**Búsqueda sin tildes.** El índice guarda el texto normalizado, así que el término buscado
debe pasar por la misma función:

```sql
SELECT * FROM productos
WHERE busqueda @@ plainto_tsquery('spanish', fn_sin_tildes('amortiguacion aire'));
```

Para tolerar erratas en el nombre está `pg_trgm` (`nike ar max` encuentra `Nike Air Max`):

```sql
SELECT * FROM productos
WHERE nombre % 'nike ar max'
ORDER BY similarity(nombre, 'nike ar max') DESC;
```

**Extensiones requeridas:** `pg_trgm` y `unaccent`. Ambas vienen en la imagen de Postgres
de Railway. En un Postgres sin el paquete `contrib`, `01_schema.sql` fallará en la primera
instrucción.

**Un local, una tienda.** Un índice único parcial impide dos tiendas activas en el mismo
local, pero permite conservar las anteriores marcándolas `activa = false`.

---

## Sobre los datos de ejemplo

Salen del contenido actual del sitio: las 6 categorías, Nike Store en el Local 215 con su
horario y sus 4 productos con precios reales, y los 4 eventos del carrusel.

Dos valores son supuestos, señalados también en los comentarios del SQL:

- **Horario dominical de Nike Store** (10:00–18:00): la ficha del sitio solo indica
  09:30–20:00 sin distinguir domingos, así que se alineó al horario general del mall.
- **Coordenadas del mapa** (4.8087, -75.6906): aproximadas a la Cra. 8 con Cll. 30 de
  Pereira. Ajústalas con la ubicación exacta si vas a usarlas para navegación.
