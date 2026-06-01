import { error } from '@sveltejs/kit';
import type { User } from '@supabase/supabase-js';
import { getSupabaseAdmin } from './supabaseAdmin';

export type LibrarianEmailRow = {
	email: string;
	created_at: string;
	created_by: string | null;
};

export function normalizeEmail(value: string) {
	return value.trim().toLowerCase();
}

export function assertValidEmail(email: string) {
	if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
		throw error(400, 'Enter a valid email address.');
	}
}

export async function requireLibrarian(request: Request) {
	const authorization = request.headers.get('authorization') ?? '';
	const token = authorization.startsWith('Bearer ') ? authorization.slice('Bearer '.length).trim() : '';

	if (!token) {
		throw error(401, 'Sign in required.');
	}

	const supabaseAdmin = getSupabaseAdmin();
	const { data, error: authError } = await supabaseAdmin.auth.getUser(token);

	if (authError || !data.user?.email) {
		throw error(401, 'Session is no longer valid.');
	}

	const email = normalizeEmail(data.user.email);
	const { data: librarian, error: librarianError } = await supabaseAdmin
		.from('librarian_emails')
		.select('email')
		.eq('email', email)
		.maybeSingle();

	if (librarianError) {
		throw error(500, librarianError.message);
	}

	if (!librarian) {
		throw error(403, 'Librarian access required.');
	}

	return {
		supabaseAdmin,
		user: data.user as User,
		email
	};
}
