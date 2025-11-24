/** @type {import('tailwindcss').Config} */
export default {
	content: ["./src/**/*.{html,js,svelte,ts}", "./node_modules/preline/dist/*.js"],
	theme: {
		extend: {
			fontFamily: {
				sans: ["Lato", "Helvetica", "sans-serif"],
			},
			colors: {
				primary: {
					DEFAULT: "#D87263",
				},
			},
		},
	},
	plugins: [],
};
