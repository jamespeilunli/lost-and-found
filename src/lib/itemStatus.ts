export const statusOptions = ["found", "claimed", "donated"] as const;

export type ItemStatus = (typeof statusOptions)[number];

export const statusLabels: Record<ItemStatus, string> = {
	found: "At library",
	claimed: "Claimed",
	donated: "Donated",
};

export const statusBadgeClasses: Record<ItemStatus, string> = {
	found: "bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-300",
	claimed: "bg-sky-100 text-sky-900 dark:bg-sky-950 dark:text-sky-300",
	donated: "bg-violet-100 text-violet-900 dark:bg-violet-950 dark:text-violet-300",
};

/** The statuses an item can be moved to from its current one. */
export const otherStatuses = Object.fromEntries(
	statusOptions.map((status) => [status, statusOptions.filter((option) => option !== status)]),
) as Record<ItemStatus, ItemStatus[]>;
