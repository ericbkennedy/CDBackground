//
//  GithubService.swift
//  ekCoreData38a
//
//  Created by Eric Kennedy on 8/14/23.
//

import Foundation

struct GithubCommit: Decodable {
    struct Commit: Decodable {
        struct Author: Decodable {
            public var name: String
            public var email: String
            public var date: String // caller must use ISO8601DateFormatter to convert
        }
        public var author: Author
        public var message: String
    }

    public var sha: String
    public var url: String
    public var commit: Commit

    // The keys must have the same name as the attributes of the Commit entity.
    var dictionaryValue: [String: Any] {
        [
            "sha": sha,
            "url": url,
            "date": ISO8601DateFormatter().date(from: commit.author.date) ?? Date(),
            "message": commit.message
        ]
    }

}

public enum ServiceError: Error {
    case network(reason: String)
    case http(statusCode: Int)
    case parsing
    case general(reason: String)
}

struct GithubService {

    func fetchCommits(newestCommitDate: String) async -> [GithubCommit]? {

        var urlString = "https://api.github.com/repos/apple/swift/commits?per_page=100"

        if newestCommitDate.isEmpty == false {
            urlString += "&since=\(newestCommitDate)"
        }

        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                  throw ServiceError.network(reason: "Response to \(url) wasn't expected HTTPURLResponse")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.http(statusCode: httpResponse.statusCode)
            }
            let changes = try JSONDecoder().decode([GithubCommit].self, from: data)

            //dump(changes)
            return changes
        } catch {
            print("error is \(error.localizedDescription)")
        }
        return nil
    }
}
