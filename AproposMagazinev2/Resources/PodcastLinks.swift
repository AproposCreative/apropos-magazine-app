import Foundation

enum PodcastLinks {
    // Remote catalog — updated automatically by scripts/podcast-auto-publish.sh
    // Token is preserved across manifest updates; app only needs this URL once.
    static let manifestURL = URL(
        string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Fmanifest.json?alt=media&token=2e7823c1-fc8f-4a77-bfe2-667acbb3ad40"
    )

    // Offline / first-launch fallback until manifest is fetched.
    static let bundledFallbackEpisodes: [PodcastEpisode] = [
        PodcastEpisode(
            id: "backrooms",
            articleId: nil,
            articleSlug: "backrooms-anmeldelse",
            title: "Backrooms",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fbackrooms-anmeldelse%2FR%C3%A6dslen_i_de_uendelige_gule_Backrooms.m4a?alt=media&token=8ddc2183-3a7a-4452-826b-360bbd6d2757"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Casper Fiil"],
            publishedDate: nil
        ),
        PodcastEpisode(
            id: "tomodachi-life-living-the-dream",
            articleId: nil,
            articleSlug: "tomodachi-life-living-the-dream",
            title: "Tomodachi Life: Living the Dream",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Ftomodachi-life-living-the-dream%2Ftomodachi-life-living-the-dream.m4a?alt=media&token=73f6189e-f9ba-4e1f-9d23-804bedc58786"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Apropos Magazine"],
            publishedDate: nil
        ),
        PodcastEpisode(
            id: "copenhell-den-store-apropos-guide",
            articleId: nil,
            articleSlug: "copenhell---den-store-apropos-guide",
            title: "Copenhell 2026: Den store Apropos-guide",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fcopenhell---den-store-apropos-guide%2Fcopenhell---den-store-apropos-guide.m4a?alt=media&token=e8e5cf79-e629-41ee-8a51-5448cb5f6f15"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Apropos Magazine"],
            publishedDate: nil
        ),
        PodcastEpisode(
            id: "farveblind-micro-pleasures",
            articleId: nil,
            articleSlug: "farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse",
            title: "Farveblind: Micro Pleasures",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Ffarveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse%2Ffarveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a?alt=media&token=bc728731-2a2a-4654-9598-d01f36f19c2b"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Apropos Magazine"],
            publishedDate: nil
        ),
        PodcastEpisode(
            id: "o-days-2026-guide",
            articleId: nil,
            articleSlug: "o-days-2026-guide",
            title: "O-DAYS 2026: Guiden",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fo-days-2026-guide%2Fo-days-2026-guide.m4a?alt=media&token=5a9dc87f-cd8b-4bc0-a43c-d75ae6265749"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Apropos Magazine"],
            publishedDate: nil
        ),
        PodcastEpisode(
            id: "another-brick-royal-arena",
            articleId: nil,
            articleSlug: "another-brick-in-the-wall-part-5-royal-arena",
            title: "Another Brick in the Wall Part 5: Royal Arena",
            subtitle: "Lyt til artiklen",
            audioURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/apropos-magazine-6004a.firebasestorage.app/o/podcasts%2Farticles%2Fanother-brick-in-the-wall-part-5-royal-arena%2Fanother-brick-in-the-wall-part-5-royal-arena.m4a?alt=media&token=574911d0-aeb0-4fb8-8b47-171630771582"),
            productionSourceURL: nil,
            duration: nil,
            artworkURL: nil,
            hosts: ["Apropos Magazine"],
            publishedDate: nil
        )
    ]
}
