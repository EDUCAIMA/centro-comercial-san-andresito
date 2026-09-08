/* ══════════════════════════════════════════════════════════════════════════
   PUENTE DE CONTENIDO
   Conecta el panel administrador con la web pública.

   Cómo funciona:
   · El panel (admin.html) guarda lo que editas en el almacenamiento del
     navegador con la clave "sae_contenido_v1".
   · La web (inicio.html / index.html) lee ese contenido al cargar y, si
     existe, reemplaza el hero, las categorías, los comercios destacados y
     los eventos. Si no existe, la página se ve exactamente igual que
     siempre: el contenido original del HTML nunca se toca.

   Limitación importante: el almacenamiento del navegador es local, así que
   los cambios se ven en el mismo computador y navegador donde se hicieron.
   Para que los vea todo el mundo hace falta un servidor con base de datos;
   este archivo es el único que habría que reemplazar ese día.
   ══════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  var CLAVE = 'sae_contenido_v1';

  /* ── Lectura y escritura ─────────────────────────────────────────────── */
  function leer() {
    try {
      var texto = global.localStorage.getItem(CLAVE);
      return texto ? JSON.parse(texto) : null;
    } catch (e) {
      return null;   // navegador sin almacenamiento o datos corruptos
    }
  }

  function guardar(datos) {
    try {
      datos.actualizado = new Date().toISOString();
      global.localStorage.setItem(CLAVE, JSON.stringify(datos));
      return { ok: true };
    } catch (e) {
      var lleno = e && (e.name === 'QuotaExceededError' || e.code === 22);
      return {
        ok: false,
        lleno: lleno,
        mensaje: lleno
          ? 'No hay espacio para más imágenes. Elimina algunas de la galería o usa direcciones web (URL) en vez de subir archivos.'
          : 'No se pudo guardar el contenido en este navegador.'
      };
    }
  }

  function borrar() {
    try { global.localStorage.removeItem(CLAVE); return true; } catch (e) { return false; }
  }

  /* ── Espacio ocupado, en KB ──────────────────────────────────────────── */
  function espacioUsado() {
    try {
      var texto = global.localStorage.getItem(CLAVE);
      return texto ? Math.round(texto.length / 1024) : 0;
    } catch (e) { return 0; }
  }

  /* ── Conversión de archivos a imágenes guardables ────────────────────
     Una foto de cámara pesa varios MB: se reduce de tamaño y se convierte
     a texto (data URL) para poder guardarla y mostrarla sin servidor.     */
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
          ctx.fillStyle = '#ffffff';            // fondo para PNG con transparencia
          ctx.fillRect(0, 0, ancho, alto);
          ctx.drawImage(img, 0, 0, ancho, alto);
          resolver(lienzo.toDataURL('image/jpeg', calidad || 0.72));
        };
        img.src = lector.result;
      };
      lector.readAsDataURL(archivo);
    });
  }

  // Peso aproximado en KB de una imagen ya convertida a data URL
  function pesoDato(dato) {
    return Math.round(String(dato || '').length * 0.75 / 1024);
  }

  // Escape de texto antes de insertarlo como HTML
  function esc(t) {
    return String(t == null ? '' : t)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  global.Contenido = {
    CLAVE: CLAVE,
    leer: leer,
    guardar: guardar,
    borrar: borrar,
    espacioUsado: espacioUsado,
    imagenADato: imagenADato,
    pesoDato: pesoDato,
    esc: esc
  };

  // Disponible de inmediato para las páginas públicas, sin esperar eventos.
  global.CONTENIDO_ADMIN = leer();
})(window);
