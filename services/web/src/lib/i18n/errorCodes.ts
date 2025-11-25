/**
 * Mapeamento de códigos de erro da API para chaves de tradução
 *
 * O backend sempre retorna mensagens em inglês, mas fornece códigos padronizados.
 * Este mapeamento permite traduzir os erros no frontend baseado nos códigos.
 */
export const API_ERROR_CODES = {
	// Erros de validação (400)
	invalid_request: "errors.invalidRequest",
	missing_fields: "errors.missingFields",

	// Erros de conflito (409)
	user_exists: "auth.signup.errors.userExists",
	user_already_confirmed: "auth.confirmation.errors.userAlreadyConfirmed",

	// Erros de confirmação (404, 422)
	user_not_found: "auth.confirmation.errors.userNotFound",
	invalid_code: "auth.confirmation.errors.invalidCode",
	expired_code: "auth.confirmation.errors.expiredCode",

	// Erros de servidor (500)
	internal_error: "errors.serverError",
} as const;

export type ApiErrorCode = keyof typeof API_ERROR_CODES;
