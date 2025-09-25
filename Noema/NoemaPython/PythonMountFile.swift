import Foundation

struct PythonMountFile: Hashable {
    let name: String
    let data: Data
    let url: URL

    init(url: URL, data: Data) {
        self.url = url
        self.name = url.lastPathComponent
        self.data = data
    }
}
