import Darwin
import Foundation

final class DirectoryMonitor {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject

    init?(
        url: URL,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        self.fileDescriptor = fileDescriptor
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )

        source.setEventHandler(handler: handler)
        source.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
