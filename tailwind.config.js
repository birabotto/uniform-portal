/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        ikeaBlue: '#0058A3',
        ikeaYellow: '#FBD914',
        ikeaNavy: '#083B70',
        softBg: '#F6F8FB',
        softBorder: '#D9E1EC',
      },
      boxShadow: {
        soft: '0 10px 30px rgba(8, 59, 112, 0.08)',
      },
    },
  },
  plugins: [],
}
