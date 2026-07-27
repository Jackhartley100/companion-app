import Foundation

/// Serialised JSON-on-disk storage shared by the file-backed repositories.
///
/// One actor owns every write so concurrent saves cannot interleave, and writes
/// go to a temporary file first and are then moved into place, so an interrupted
/// write leaves the previous good file intact rather than a truncated one.
public actor FileStore {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Route files reach a few hundred kilobytes; pretty-printing them would
        // roughly double that for no benefit.
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// The default location: Application Support, which is backed up and is the
    /// documented home for data the user does not manage as files.
    public static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Companion", isDirectory: true)
    }

    private func url(for path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return url
    }

    public func read<T: Decodable & Sendable>(_ type: T.Type, from path: String) throws -> T? {
        let url = try url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return nil }
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw RepositoryError.decodingFailed(String(describing: error))
        } catch {
            throw RepositoryError.readFailed(error.localizedDescription)
        }
    }

    public func write<T: Encodable & Sendable>(_ value: T, to path: String) throws {
        let url = try url(for: path)
        do {
            let data = try encoder.encode(value)
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } catch let error as EncodingError {
            throw RepositoryError.writeFailed(String(describing: error))
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    public func delete(path: String) throws {
        let url = try url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    public func deleteDirectory(_ path: String) throws {
        let url = root.appendingPathComponent(path, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    public func writeData(_ data: Data, to path: String) throws {
        let url = try url(for: path)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    public func readData(from path: String) throws -> Data? {
        let url = try url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }
}
