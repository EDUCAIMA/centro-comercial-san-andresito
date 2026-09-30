/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './index.html',
    './inicio.html',
    './comercios.html',
    './quienes-somos.html',
    './privacidad.html',
    './terminos.html',
    './tienda.html',
    './contenido.js'
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: '#D97C2B',
        'primary-hover': '#bf681c',
        secondary: '#D99923',
        background: '#F2F2F2',
        surface: '#F2F2F2',
        onyx: '#0D0D0D',
        'on-surface': '#0D0D0D'
      },
      fontFamily: {
        outfit: ['Outfit', 'sans-serif'],
        grotesk: ['Hanken Grotesk', 'sans-serif']
      }
    }
  },
  plugins: [require('@tailwindcss/forms')]
};
