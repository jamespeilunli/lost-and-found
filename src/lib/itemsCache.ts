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

// Identifies one fetched slice of the inventory. Everything that changes which
// rows come back is here, and keyFor() below is the single place that turns it
// into a cache key — callers pass meaning, not pre-formatted key fragments.
export type ItemsQuery = {
	scope: ItemsScope;
	showDeleted: boolean;
	// The signed-in user's id (or null for anonymous/public reads). Folded into
	// the key so a cached entry can never be served to a different auth identity
	// than the one it was fetched for — e.g. if the session in this tab changes
	// without an explicit invalidateItemsCache() call, the old entry simply won't
	// match the new identity's key.
	identity: string | null;
	// The page index, or "all" for the full search corpus.
	page: number | "all";
	// The exact status values the query filtered on.
	statuses: string[];
};

// Short-lived cache of the inventory list, shared across every mount of the
// dashboard route. Returning to the list within the TTL reuses the last fetch
// instead of hitting the database again. The manual Refresh button forces a
// fresh fetch; every mutation clears the cache so changes show up immediately.
const TTL_MS = 30_000;

export type CachedItems = { rows: ItemRow[]; count: number };

type CacheEntry = { at: number } & CachedItems;

const cache = new Map<string, CacheEntry>();

function keyFor(q: ItemsQuery): string {
	const pageKey = q.page === "all" ? "all" : `p${q.page}`;
	const statusKey = [...q.statuses].sort().join(",") || "none";
	return `${q.scope}:${q.showDeleted}:${q.identity ?? "anon"}:${pageKey}:${statusKey}`;
}

/** Cached rows + total count for this query, or null when there is no entry or it has expired. */
export function getCachedItems(q: ItemsQuery): CachedItems | null {
	const key = keyFor(q);
	const entry = cache.get(key);
	if (!entry) return null;
	if (Date.now() - entry.at >= TTL_MS) {
		cache.delete(key);
		return null;
	}
	const { at: _at, ...items } = entry;
	return items;
}

export function setCachedItems(q: ItemsQuery, rows: ItemRow[], count: number): void {
	cache.set(keyFor(q), { at: Date.now(), rows, count });
}

/**
 * Drop every cached scope. A single item change can affect more than one view
 * (the public list, the librarian list, the archive), and the dataset is small,
 * so clearing all of it on any mutation is simplest and always correct.
 */
export function invalidateItemsCache(): void {
	cache.clear();
}
