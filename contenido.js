/* ══════════════════════════════════════════════════════════════════════════
   PUENTE DE CONTENIDO - CONEXIÓN CON SERVIDOR Y API CLOUD
   Conecta el panel administrador con la web pública y el servidor en Railway.

   Cómo funciona:
   · Si hay conexión con el servidor (/api/contenido), sincroniza y lee el
     contenido persistido en la base de datos de la nube.
   · Si se edita en el panel (admin.html), se envía mediante POST a la nube
     para que cualquier visitante en cualquier dispositivo lo vea.
   · Mantiene localStorage como fallback instantáneo y respaldo offline.
   ══════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  var CLAVE = 'sae_contenido_v1';
  var API_URL = '/api/contenido';

  /* ── Lectura sincrónica (desde cache/localStorage) ──────────────────── */
  function leer() {
    try {
      var texto = global.localStorage.getItem(CLAVE);
      return texto ? JSON.parse(texto) : null;
    } catch (e) {
      return null;
    }
  }

  /* ── Sincronización asincrónica con la API en la nube ───────────────── */
  function sincronizarConServidor() {
    return fetch(API_URL)
      .then(function (res) {
        if (!res.ok) throw new Error('Error al consultar API: ' + res.status);
        return res.json();
      })
      .then(function (respuesta) {
        if (respuesta && respuesta.ok) {
          var remoto = respuesta.data;
          var local = leer();

          // Caso 1: El servidor remoto aún está vacío (null/undefined) pero este navegador tiene datos editados
          if (!remoto || (typeof remoto === 'object' && Object.keys(remoto).length === 0)) {
            if (local && Object.keys(local).length > 0) {
              // Subir automáticamente el contenido local a la nube de Railway
              guardarEnServidor(local);
              return { ok: true, datos: local, actualizado: false };
            }
            return { ok: true, datos: null, actualizado: false };
          }

          // Caso 2: Hay datos en el servidor remoto
          var remotoTime = remoto.actualizado ? new Date(remoto.actualizado).getTime() : 1;
          var localTime = (local && local.actualizado) ? new Date(local.actualizado).getTime() : 0;

          if (!local || remotoTime > localTime) {
            // El servidor tiene datos nuevos y más recientes (o este navegador estaba limpio)
            try {
              global.localStorage.setItem(CLAVE, JSON.stringify(remoto));
            } catch (e) {}
            global.CONTENIDO_ADMIN = remoto;
            return { ok: true, datos: remoto, actualizado: true };
          } else if (remotoTime < localTime) {
            // El navegador local tiene una edición más reciente que aún no subió
            guardarEnServidor(local);
            return { ok: true, datos: local, actualizado: false };
          } else {
            // Datos sincronizados (remotoTime === localTime)
            return { ok: true, datos: remoto, actualizado: false };
          }
        }
        return { ok: true, datos: leer(), actualizado: false };
      })
      .catch(function (err) {
        // Fallback silencioso en caso de no haber red o estar en ambiente estático
        return { ok: false, error: err, datos: leer() };
      });
  }

  /* ── Guardar tanto en servidor remoto como en local ─────────────────── */
  function guardarEnServidor(datos) {
    return fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(datos)
    })
    .then(function (res) { return res.json(); })
    .catch(function (err) {
      console.warn('No se pudo guardar en la nube (offline o error):', err);
      return { ok: false, error: err };
    });
  }

  function guardar(datos) {
    try {
      datos.actualizado = new Date().toISOString();
      global.localStorage.setItem(CLAVE, JSON.stringify(datos));
      global.CONTENIDO_ADMIN = datos;

      // Disparar envío a la nube de inmediato
      var promesaCloud = guardarEnServidor(datos);

      return {
        ok: true,
        cloud: promesaCloud
      };
    } catch (e) {
      var lleno = e && (e.name === 'QuotaExceededError' || e.code === 22);
      return {
        ok: false,
        lleno: lleno,
        mensaje: lleno
          ? 'No hay espacio para más imágenes en el navegador. Reduce la resolución o usa URLs directas.'
          : 'No se pudo guardar el contenido.'
      };
    }
  }

  function borrar() {
    try {
      global.localStorage.removeItem(CLAVE);
      guardarEnServidor({});
      return true;
    } catch (e) {
      return false;
    }
  }

  /* ── Espacio ocupado, en KB ──────────────────────────────────────────── */
  function espacioUsado() {
    try {
      var texto = global.localStorage.getItem(CLAVE);
      return texto ? Math.round(texto.length / 1024) : 0;
    } catch (e) { return 0; }
  }

  /* ── Conversión de archivos a imágenes guardables ──────────────────── */
  function imagenADato(archivo, anchoMax, calidad) {
    return new Promise(function (resolver, rechazar) {
      if (!archivo || !/^image\//.test(archivo.type)) {
        rechazar(new Error('El archivo seleccionado no es una imagen.'));
        return;
      }
      var lector = new FileReader();
      lector.onerror = function () { rechazar(new Error('No se pudo leer el archivo.')); };
      lector.onload = function () {
        var img = new Image();
        img.onerror = function () { rechazar(new Error('La imagen está dañada o no se puede abrir.')); };
        img.onload = function () {
          var escala = Math.min(1, (anchoMax || 1400) / img.naturalWidth);
          var ancho = Math.max(1, Math.round(img.naturalWidth * escala));
          var alto  = Math.max(1, Math.round(img.naturalHeight * escala));
          var lienzo = document.createElement('canvas');
          lienzo.width = ancho;
          lienzo.height = alto;
          var ctx = lienzo.getContext('2d');
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(0, 0, ancho, alto);
          ctx.drawImage(img, 0, 0, ancho, alto);
          resolver(lienzo.toDataURL('image/jpeg', calidad || 0.72));
        };
        img.src = lector.result;
      };
      lector.readAsDataURL(archivo);
    });
  }

  function pesoDato(dato) {
    return Math.round(String(dato || '').length * 0.75 / 1024);
  }

  function esc(t) {
    return String(t == null ? '' : t)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  global.Contenido = {
    CLAVE: CLAVE,
    leer: leer,
    guardar: guardar,
    guardarEnServidor: guardarEnServidor,
    sincronizarConServidor: sincronizarConServidor,
    borrar: borrar,
    espacioUsado: espacioUsado,
    imagenADato: imagenADato,
    pesoDato: pesoDato,
    esc: esc
  };

  // Inicializar contenido local de inmediato para el renderizado
  global.CONTENIDO_ADMIN = leer();

  // Y sincronizar asincrónicamente con la nube si hay conexión
  if (typeof fetch === 'function') {
    sincronizarConServidor().then(function (res) {
      if (res && res.actualizado) {
        // Si hay contenido nuevo traído de la nube y la página tiene funciones de refresco, invocarlas
        if (typeof global.alActualizarContenidoNube === 'function') {
          global.alActualizarContenidoNube(res.datos);
        }
      }
    });
  }
})(window);
