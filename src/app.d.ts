// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}

	namespace ImportMetaEnv {
		readonly PUBLIC_SUPABASE_URL: string;
		readonly PUBLIC_SUPABASE_ANON_KEY: string;
	}

	interface ImportMeta {
		readonly env: ImportMetaEnv;
	}
}

export {};
