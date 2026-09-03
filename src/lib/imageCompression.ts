import imageCompression from 'browser-image-compression';

// Item photos are only ever shown in ~640px cards and 48px table thumbnails, so a
// 1280px WebP is plenty and keeps stored objects (and the bandwidth to serve them)
// small. Phone photos are typically several MB; this brings them to a few hundred KB.
const MAX_DIMENSION = 1280;
const MAX_SIZE_MB = 0.3;

// Anything already this small isn't worth re-encoding.
const SKIP_BELOW_BYTES = 200 * 1024;

/**
 * Downscale + re-encode an image chosen for upload. Best-effort: anything that
 * can't or shouldn't be compressed (non-raster, already small, or a failure in
 * the encoder) falls through and the original file is returned unchanged.
 */
export async function compressImage(file: File): Promise<File> {
	if (!file.type.startsWith('image/')) return file;
	// SVG is vector; GIF may be animated — re-rastering either loses information.
	if (file.type === 'image/svg+xml' || file.type === 'image/gif') return file;
	if (file.size <= SKIP_BELOW_BYTES) return file;

	try {
		const compressed = await imageCompression(file, {
			maxWidthOrHeight: MAX_DIMENSION,
			maxSizeMB: MAX_SIZE_MB,
			useWebWorker: true,
			fileType: 'image/webp',
			initialQuality: 0.8
		});

		// If re-encoding somehow grew the file, keep the original.
		return compressed.size < file.size ? compressed : file;
	} catch (err) {
		console.warn('Image compression failed, uploading original:', err);
		return file;
	}
}

/** File extension for the storage path, derived from the (possibly re-encoded) type. */
export function extensionForType(file: File, fallbackName: string): string {
	switch (file.type) {
		case 'image/webp':
			return 'webp';
		case 'image/jpeg':
			return 'jpg';
		case 'image/png':
			return 'png';
		default:
			return fallbackName.split('.').pop() || 'jpg';
	}
}
