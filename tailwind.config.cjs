const colors = require("tailwindcss/colors");

module.exports = {
  content: ["./templates/*.{html}", "./templates/**/*.{html}"],
  darkMode: false,
  theme: {
    extend: {},
  },
  variants: {
    extend: {},
  },
  plugins: [require("@tailwindcss/forms")],
};
