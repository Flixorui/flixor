import Foundation
import Nuke

enum PrefetchKind { case poster, landscape, backdrop }

final class TVImagePrefetch {
    static let shared = TVImagePrefetch()
    private let prefetcher = ImagePrefetcher(pipeline: ImagePipeline.shared)

    func prefetch(urls: [URL]) {
        prefetcher.stopPrefetching() // keep queue small
        prefetcher.startPrefetching(with: urls)
    }
}

