/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./admin.html', './admin-login.html'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: '#D97C2B',
        'primary-hover': '#bf681c',
        secondary: '#D99923',
        background: '#F2F2F2',
        surface: '#FFFFFF',
        onyx: '#0D0D0D',
        muted: '#5a534e'
      },
      fontFamily: {
        outfit: ['Outfit', 'sans-serif'],
        grotesk: ['Hanken Grotesk', 'sans-serif']
      }
    }
  },
  plugins: []
};
