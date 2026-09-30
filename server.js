const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 8080;

// Directorio de persistencia de datos (en Railway se puede montar un volumen aquí)
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const CONTENIDO_FILE = path.join(DATA_DIR, 'contenido.json');
const DATABASE_URL = process.env.DATABASE_URL;
const pool = DATABASE_URL
  ? new Pool({
      connectionString: DATABASE_URL,
      max: 5,
      ssl: process.env.DATABASE_SSL === 'true'
        ? { rejectUnauthorized: false }
        : undefined
    })
  : null;
let baseDatosLista = false;

// Asegurar que el directorio de datos existe
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Cargar contenido persistido o devolver null
function leerContenidoPersistido() {
  try {
    if (fs.existsSync(CONTENIDO_FILE)) {
      const data = fs.readFileSync(CONTENIDO_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (err) {
    console.error('Error al leer contenido persistido:', err);
  }
  return null;
}

// Guardar contenido en disco
function guardarContenidoPersistido(data) {
  try {
    fs.writeFileSync(CONTENIDO_FILE, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (err) {
    console.error('Error al guardar contenido persistido:', err);
    return false;
  }
}

// Inicializar PostgreSQL y migrar el JSON local solo si la tabla está vacía.
async function inicializarBaseDatos() {
  if (!pool) return;

  await pool.query(`
    CREATE TABLE IF NOT EXISTS contenido_sitio (
      id SMALLINT PRIMARY KEY CHECK (id = 1),
      data JSONB NOT NULL,
      actualizado TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const resultado = await pool.query(
    'SELECT data FROM contenido_sitio WHERE id = 1'
  );

  if (resultado.rowCount === 0) {
    const contenidoLocal = leerContenidoPersistido();
    if (contenidoLocal) {
      await pool.query(
        `INSERT INTO contenido_sitio (id, data, actualizado)
         VALUES (1, $1::jsonb, COALESCE($2::timestamptz, NOW()))`,
        [
          JSON.stringify(contenidoLocal),
          contenidoLocal.actualizado || null
        ]
      );
      console.log('Contenido local migrado a PostgreSQL');
    }
  }

  baseDatosLista = true;
  console.log('Persistencia activa: PostgreSQL');
}

async function leerContenido() {
  if (!baseDatosLista) return leerContenidoPersistido();

  const resultado = await pool.query(
    'SELECT data FROM contenido_sitio WHERE id = 1'
  );
  return resultado.rowCount ? resultado.rows[0].data : null;
}

async function guardarContenido(data) {
  if (!baseDatosLista) return guardarContenidoPersistido(data);

  await pool.query(
    `INSERT INTO contenido_sitio (id, data, actualizado)
     VALUES (1, $1::jsonb, $2::timestamptz)
     ON CONFLICT (id) DO UPDATE SET
       data = EXCLUDED.data,
       actualizado = EXCLUDED.actualizado`,
    [JSON.stringify(data), data.actualizado]
  );
  return true;
}

app.use(cors());
// Permitir imágenes y contenidos grandes (hasta 50MB) en base64
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// API Endpoints
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    database: baseDatosLista ? 'postgresql' : 'file',
    timestamp: new Date().toISOString()
  });
});

app.get('/api/contenido', async (req, res) => {
  try {
    const contenido = await leerContenido();
    res.json({ ok: true, data: contenido });
  } catch (err) {
    console.error('Error al leer contenido desde PostgreSQL:', err);
    res.status(500).json({ ok: false, mensaje: 'Error al leer el contenido' });
  }
});

app.post('/api/contenido', async (req, res) => {
  const payload = req.body;
  if (!payload || typeof payload !== 'object') {
    return res.status(400).json({ ok: false, mensaje: 'Payload inválido' });
  }

  payload.actualizado = new Date().toISOString();

  try {
    await guardarContenido(payload);
    res.json({ ok: true, mensaje: 'Contenido guardado correctamente en el servidor' });
  } catch (err) {
    console.error('Error al guardar contenido en PostgreSQL:', err);
    res.status(500).json({ ok: false, mensaje: 'Error al persistir en el servidor' });
  }
});

// Servir archivos estáticos
app.use(express.static(path.join(__dirname), {
  extensions: ['html', 'htm']
}));

// Fallback a index.html para rutas tipo SPA o limpias
app.get('*', (req, res) => {
  const ruta = path.join(__dirname, req.path);
  if (fs.existsSync(ruta) && fs.statSync(ruta).isFile()) {
    return res.sendFile(ruta);
  }
  const rutaHtml = path.join(__dirname, `${req.path}.html`);
  if (fs.existsSync(rutaHtml) && fs.statSync(rutaHtml).isFile()) {
    return res.sendFile(rutaHtml);
  }
  res.sendFile(path.join(__dirname, 'index.html'));
});

async function iniciarServidor() {
  if (pool) {
    await inicializarBaseDatos();
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Servidor iniciado en http://0.0.0.0:${PORT}`);
  });
}

iniciarServidor().catch((err) => {
  console.error('No se pudo inicializar la persistencia:', err);
  process.exit(1);
});
