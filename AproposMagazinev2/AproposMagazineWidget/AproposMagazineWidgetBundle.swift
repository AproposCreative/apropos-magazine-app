import WidgetKit
import SwiftUI

@main
struct AproposMagazineWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestArticleWidget()
        AproposTodayWidget()
        PodcastLiveActivityWidget()
    }
}
