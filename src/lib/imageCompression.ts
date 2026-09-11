import imageCompression from 'browser-image-compression';

// Item photos are only ever shown in ~640px cards and 48px table thumbnails, so a
// 1280px WebP is plenty and keeps stored objects (and the bandwidth to serve them)
// small. Phone photos are typically several MB; this brings them to a few hundred KB.
const MAX_DIMENSION = 1280;
const MAX_SIZE_MB = 0.3;

/**
 * Animated GIFs can't be safely re-encoded (the compressor only produces a single
 * static frame), so they're rejected outright at file-selection time rather than
 * silently passed through raw or silently flattened. Call this before accepting a
 * file from a file input; a non-null return is a user-facing error message.
 */
export function getImageRejectionReason(file: File): string | null {
	const isGif = file.type === 'image/gif' || /\.gif$/i.test(file.name);
	if (isGif) {
		return 'Animated GIFs aren\'t supported. Please upload a JPEG, PNG, WebP, or SVG image instead.';
	}
	return null;
}

/**
 * Downscale + re-encode an image chosen for upload. Best-effort: anything that
 * can't or shouldn't be compressed (non-raster, or a failure in the encoder)
 * falls through and the original file is returned unchanged. Every raster photo
 * (including SVG, which the encoder rasterizes) is compressed regardless of size,
 * since even small files can carry EXIF/location metadata worth stripping.
 */
export async function compressImage(file: File): Promise<File> {
	if (!file.type.startsWith('image/')) return file;
	// GIFs should have been rejected before this is called; defensively skip
	// re-encoding one rather than silently flattening it to a static frame.
	if (file.type === 'image/gif') return file;

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
