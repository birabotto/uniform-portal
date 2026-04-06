/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        ikeaBlue: '#0058A3',
        ikeaYellow: '#FFDA1A',
        ink: '#111827',
      },
      fontFamily: {
        sans: ['Noto Sans', 'sans-serif'],
      },
      boxShadow: {
        soft: '0 12px 30px rgba(17, 24, 39, 0.08)',
      },
    },
  },
  plugins: [],
}
