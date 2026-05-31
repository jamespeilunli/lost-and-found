import { json, error } from '@sveltejs/kit';
import { assertValidEmail, normalizeEmail, requireLibrarian } from '$lib/server/librarianAuth';

async function findAuthUserByEmail(
	supabaseAdmin: ReturnType<typeof import('$lib/server/supabaseAdmin').getSupabaseAdmin>,
	email: string
) {
	const { data, error: listError } = await supabaseAdmin.auth.admin.listUsers({
		page: 1,
		perPage: 1000
	});

	if (listError) {
		throw error(500, listError.message);
	}

	return data.users.find((user) => normalizeEmail(user.email ?? '') === email) ?? null;
}

export async function GET({ request }) {
	const { supabaseAdmin } = await requireLibrarian(request);

	const { data, error: listError } = await supabaseAdmin
		.from('librarian_emails')
		.select('email,created_at,created_by')
		.order('email', { ascending: true });

	if (listError) {
		throw error(500, listError.message);
	}

	return json({ emails: data ?? [] });
}

export async function POST({ request, url }) {
	const { supabaseAdmin, user } = await requireLibrarian(request);
	const body = (await request.json().catch(() => null)) as { email?: string } | null;
	const email = normalizeEmail(body?.email ?? '');
	assertValidEmail(email);

	const { data: row, error: upsertError } = await supabaseAdmin
		.from('librarian_emails')
		.upsert({ email, created_by: user.id }, { onConflict: 'email' })
		.select('email,created_at,created_by')
		.single();

	if (upsertError) {
		throw error(500, upsertError.message);
	}

	const redirectTo = `${url.origin}/set-password`;
	const { error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
		redirectTo
	});

	if (inviteError) {
		return json(
			{
				email: row,
				warning: `The email was approved, but the invite could not be sent: ${inviteError.message}`
			},
			{ status: 202 }
		);
	}

	return json({ email: row });
}

export async function DELETE({ request }) {
	const { supabaseAdmin, email: requesterEmail } = await requireLibrarian(request);
	const body = (await request.json().catch(() => null)) as { email?: string } | null;
	const email = normalizeEmail(body?.email ?? '');
	assertValidEmail(email);

	if (email === requesterEmail) {
		throw error(400, "You can't remove your own librarian account.");
	}

	const { error: deleteWhitelistError } = await supabaseAdmin
		.from('librarian_emails')
		.delete()
		.eq('email', email);

	if (deleteWhitelistError) {
		throw error(500, deleteWhitelistError.message);
	}

	const authUser = await findAuthUserByEmail(supabaseAdmin, email);
	if (!authUser) {
		return json({ removed: true, warning: 'Whitelist removed; no matching Auth user was found.' });
	}

	const { error: deleteUserError } = await supabaseAdmin.auth.admin.deleteUser(authUser.id);
	if (deleteUserError) {
		return json(
			{
				removed: true,
				warning: `Whitelist removed, but the Auth user could not be deleted: ${deleteUserError.message}`
			},
			{ status: 202 }
		);
	}

	return json({ removed: true });
}
