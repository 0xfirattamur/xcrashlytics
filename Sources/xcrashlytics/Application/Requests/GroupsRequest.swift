struct GroupsRequest: Sendable {
    var issue: String?
    var firebaseLimit: Int
    var limit: Int?
    var since: String?
    var includesXcode: Bool
    var crashDirectories: [String]
}
