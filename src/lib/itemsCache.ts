export type ItemStatus = "found" | "claimed";

export type ItemRow = {
	id: string;
	title: string;
	description: string | null;
	category: string | null;
	status: ItemStatus;
	image_url: string | null;
	location_found: string | null;
	created_at: string;
	manual_due_date: string | null;
	claimed_by_email: string | null;
};

export type ItemsScope = "public" | "librarian";

// Short-lived cache of the inventory list, shared across every mount of the
// dashboard route. Returning to the list within the TTL reuses the last fetch
// instead of hitting the database again. The manual Refresh button forces a
// fresh fetch; every mutation clears the cache so changes show up immediately.
const TTL_MS = 30_000;

type CacheEntry = { at: number; rows: ItemRow[] };

const cache = new Map<string, CacheEntry>();

function keyFor(scope: ItemsScope, showDeleted: boolean): string {
	return `${scope}:${showDeleted}`;
}

/** Cached rows for this scope, or null when there is no entry or it has expired. */
export function getCachedItems(scope: ItemsScope, showDeleted: boolean): ItemRow[] | null {
	const key = keyFor(scope, showDeleted);
	const entry = cache.get(key);
	if (!entry) return null;
	if (Date.now() - entry.at >= TTL_MS) {
		cache.delete(key);
		return null;
	}
	return entry.rows;
}

export function setCachedItems(scope: ItemsScope, showDeleted: boolean, rows: ItemRow[]): void {
	cache.set(keyFor(scope, showDeleted), { at: Date.now(), rows });
}

/**
 * Drop every cached scope. A single item change can affect more than one view
 * (the public list, the librarian list, the archive), and the dataset is small,
 * so clearing all of it on any mutation is simplest and always correct.
 */
export function invalidateItemsCache(): void {
	cache.clear();
}
