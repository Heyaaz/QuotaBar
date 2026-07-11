import Foundation

final class JSONLineProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private let timeout: DispatchWorkItem

    init(executable: String, arguments: [String], timeoutSeconds: TimeInterval = 10) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProviderError.processFailed(error.localizedDescription)
        }

        timeout = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func read(id: Int) throws -> Data {
        while true {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard
                    let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                    object["id"] as? Int == id
                else { continue }
                return Data(line)
            }

            guard let chunk = try output.fileHandleForReading.read(upToCount: 1), !chunk.isEmpty else {
                throw ProviderError.timedOut
            }
            buffer.append(chunk)
        }
    }

    func close() {
        timeout.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    deinit {
        close()
    }
}
