import { randomUUID } from 'node:crypto';

export const BUCKET = 'apropos-magazine-6004a.firebasestorage.app';

export function publicURL(storagePath, token) {
  const encoded = encodeURIComponent(storagePath);
  let url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media`;
  if (token) url += `&token=${token}`;
  return url;
}

export function extractToken(metadata) {
  const raw = metadata?.metadata?.firebaseStorageDownloadTokens;
  if (!raw) return null;
  return String(raw).split(',')[0].trim() || null;
}

export async function resolveDownloadToken(bucket, storagePath) {
  try {
    const [metadata] = await bucket.file(storagePath).getMetadata();
    const existing = extractToken(metadata);
    if (existing) return existing;
  } catch (error) {
    if (error?.code !== 404) {
      console.warn(`Could not read token for ${storagePath}: ${error.message}`);
    }
  }
  return randomUUID();
}
