# Podcast Audio Workflow (v1)

## 1) Short overview

NotebookLM is only used to **generate/export** podcast audio for an article.  
The app never opens NotebookLM for playback.

The app only plays **direct hosted audio URLs** (for example `.mp3`, `.m4a`, `.aac`, `.wav`, `.mp4`, `.m3u8`) through native `AVPlayer` inside Apropos Magazine.

## 2) Recommended Firebase Storage structure

Use this folder pattern in Firebase Storage:

```text
podcasts/articles/{articleSlug}/audio.mp3
podcasts/articles/{articleSlug}/artwork.jpg
```

Example:

```text
podcasts/articles/backrooms-a24/audio.mp3
podcasts/articles/backrooms-a24/artwork.jpg
```

## 3) Export from NotebookLM

1. Generate the podcast in NotebookLM.
2. Export/download the audio file to your machine.
3. Rename it cleanly (recommended `audio.mp3` or `audio.m4a`).

Example local export path:

```text
/Users/frederikkragh/Downloads/Rædslen_i_de_uendelige_gule_Backrooms.m4a
```

## 4) Upload to Firebase Storage (v1)

For v1, upload manually in Firebase Console:

1. Open Firebase Console -> Storage.
2. Navigate to `podcasts/articles/{articleSlug}/`.
3. Upload:
   - `audio.mp3` (or `audio.m4a`)
   - `artwork.jpg` (optional but recommended)

Team upload is manual in Console for v1. App users do not upload files.

## 5) Get the direct download URL

After upload:

1. Select the uploaded audio file in Firebase Storage.
2. Copy its public/direct download URL.
3. Put that URL into `audioURL` in:

`AproposMagazinev2/Resources/PodcastLinks.swift`

## 6) Update `PodcastLinks.swift`

Example entry:

```swift
PodcastEpisode(
    id: "backrooms-a24",
    articleId: nil,
    articleSlug: "backrooms-a24",
    title: "Backrooms",
    subtitle: "Lyt til artiklen",
    audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/<bucket>/o/podcasts%2Farticles%2Fbackrooms-a24%2Faudio.m4a?alt=media&token=<token>"),
    productionSourceURL: URL(string: "https://notebooklm.google.com/notebook/..."), // internal reference only
    duration: "12:40",
    artworkURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/<bucket>/o/podcasts%2Farticles%2Fbackrooms-a24%2Fartwork.jpg?alt=media&token=<token>"),
    hosts: ["Apropos Magazine"],
    publishedDate: nil
)
```

Important:

- `audioURL` must be a direct playable URL (`.mp3`, `.m4a`, `.aac`, `.wav`, `.mp4`, `.m3u8`).
- `productionSourceURL` is internal metadata only and is never opened by the app.
- NotebookLM URLs must never be pasted into `audioURL`.

## 7) Firebase Storage rules (suggested for v1)

Suggested direction (verify in Firebase Console before production):

- Public read under `/podcasts/articles/**`
- No client write access from the app

Suggested rules template:

```text
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /podcasts/articles/{allPaths=**} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

Note: exact rules can be project-dependent. Validate with your Firebase security requirements before final production release.

## 8) QA checklist after adding audio

- Open app
- Confirm Podcast section shows the episode
- Open article
- Confirm `Lyt til artiklen` appears
- Tap button
- Confirm native player sheet opens
- Confirm playback starts
- Confirm no Google/NotebookLM/account login appears
- Test light mode and dark mode
- Test on real device if possible

## 9) Future improvements

Optional post-launch improvements:

- Remote config/API for podcast metadata instead of local `PodcastLinks.swift`
- Offline caching/download
- Lock screen controls
- Background audio
- Now Playing integration
- Analytics for plays/completions

