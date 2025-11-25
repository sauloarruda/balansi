import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig } from "vite";


export default defineConfig({
	plugins: [sveltekit()],
	server: {
		port: 8080,
		proxy: {
			'/auth': {
				target: process.env.VITE_API_PROXY_TARGET || 'http://localhost:3000',
				changeOrigin: true,
				cookieDomainRewrite: "",
				bypass: (req, res, options) => {
					if (req.headers.accept && req.headers.accept.includes('text/html')) {
						return req.url;
					}
				}
			}
		}
	},
	preview: {
		port: 8081,
		proxy: {
			'/auth': {
				target: process.env.VITE_API_PROXY_TARGET || 'http://localhost:3000',
				changeOrigin: true,
				cookieDomainRewrite: "",
				bypass: (req, res, options) => {
					if (req.headers.accept && req.headers.accept.includes('text/html')) {
						return req.url;
					}
				}
			}
		}
	}
});
