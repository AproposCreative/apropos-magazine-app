// Keep this orchestration free of Firebase imports so publishing order and
// --no-notify can be verified without credentials or network access.
export async function publishManifestThenNotify({
  syncManifest,
  notifications,
  notify,
  noNotify = false,
  onError = () => {},
}) {
  const published = await syncManifest();
  if (published?.published !== true || !Array.isArray(published?.manifest?.episodes)) throw new Error("Missing accepted manifest");
  if (noNotify) return;
  for (const notification of notifications) {
    try {
      const accepted = published.manifest.episodes.some((episode) =>
        episode.articleSlug === notification.slug &&
        (episode.kind === "ai") === (notification.kind === "ai") &&
        (!notification.audioURL || episode.audioURL === notification.audioURL) &&
        (!notification.sourceContentRevision || episode.sourceContentRevision === notification.sourceContentRevision));
      if (!accepted) throw new Error("Notification episode was not accepted into manifest");
      await notify(notification);
    } catch (error) {
      onError(error);
    }
  }
}
