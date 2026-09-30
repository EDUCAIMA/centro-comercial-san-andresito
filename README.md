# Centro Comercial San Andresito del Eje - Pereira

Sitio web oficial y directorio interactivo del Centro Comercial San Andresito del Eje, ubicado en Pereira, Risaralda.

## Tecnologías
- HTML5 / CSS3 (Tailwind CSS compilado localmente)
- JavaScript Vanilla (Carrusel interactivo, filtros y buscador de tiendas)
- Google Fonts & Material Symbols
- Caddy / Web Server estático

## Estructura de archivos
- `index.html` / `inicio.html`: Página principal con hero interactivo, comercios y carrusel de eventos.
- `tienda.html`: Ficha de local comercial con catálogo de productos y filtros laterales.
- `admin.html`: Panel administrativo de gestión.

## Ejecución local

```bash
npm install
npm start
```

El sitio queda disponible en `http://localhost:8080`.

En local, si no existe `DATABASE_URL`, el servidor usa `data/contenido.json` como respaldo. En Railway, al configurar `DATABASE_URL`, crea automáticamente la tabla de contenido y migra ese archivo una sola vez a PostgreSQL.

## Estilos locales

Tailwind se compila en dos archivos para conservar las configuraciones de la web pública y del panel administrativo:

```bash
npm run build:css
```

Después de agregar o modificar clases de Tailwind en los archivos HTML o JavaScript, ejecuta ese comando antes de publicar. Durante el desarrollo también se pueden observar los cambios con `npm run watch:css:public` o `npm run watch:css:admin`.
