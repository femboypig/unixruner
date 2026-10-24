import Foundation

public enum DownloadState: Equatable {
    case idle
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case completed(localURL: URL)
    case failed(error: String)
}

public final class AssetDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published public private(set) var state: DownloadState = .idle

    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var destinationURL: URL?
    private var completionHandler: ((Result<URL, Error>) -> Void)?

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    public func download(from sourceURL: URL, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.destinationURL = destinationURL
        self.completionHandler = completion
        self.state = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: 0)

        self.downloadTask = session.downloadTask(with: sourceURL)
        self.downloadTask?.resume()
    }

    public func cancel() {
        downloadTask?.cancel()
        state = .idle
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0
        self.state = .downloading(
            progress: progress,
            bytesWritten: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite
        )
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = destinationURL else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            self.state = .completed(localURL: dest)
            self.completionHandler?(.success(dest))
        } catch {
            self.state = .failed(error: error.localizedDescription)
            self.completionHandler?(.failure(error))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            self.state = .failed(error: error.localizedDescription)
            self.completionHandler?(.failure(error))
        }
    }
}
