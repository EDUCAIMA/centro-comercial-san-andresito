const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 8080;

// Directorio de persistencia de datos (en Railway se puede montar un volumen aquí)
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const CONTENIDO_FILE = path.join(DATA_DIR, 'contenido.json');

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

app.use(cors());
// Permitir imágenes y contenidos grandes (hasta 50MB) en base64
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// API Endpoints
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/api/contenido', (req, res) => {
  const contenido = leerContenidoPersistido();
  res.json({ ok: true, data: contenido });
});

app.post('/api/contenido', (req, res) => {
  const payload = req.body;
  if (!payload || typeof payload !== 'object') {
    return res.status(400).json({ ok: false, mensaje: 'Payload inválido' });
  }

  payload.actualizado = new Date().toISOString();
  const guardado = guardarContenidoPersistido(payload);

  if (guardado) {
    res.json({ ok: true, mensaje: 'Contenido guardado correctamente en el servidor' });
  } else {
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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Servidor iniciado en http://0.0.0.0:${PORT}`);
});
