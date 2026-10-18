#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Sample kanban answers for previews. They are decoded from the server's JSON shape, so the previews read the same
    /// models the app reads.
    enum KanbanSampleData {
        static let board: KanbanBoardView? = decode(KanbanBoardView.self, boardJSON)
        static let readyColumn: KanbanColumn? = board?.columns.first { $0.name == "ready" }
        static let columnNames: [String] = board?.columns.map(\.name) ?? []
        static let assignees: [String] = board?.assignees ?? []
        static let boards: [KanbanBoardInfo] = decode(KanbanBoards.self, boardsJSON)?.boards ?? []
        static let detail: KanbanTaskDetail? = decode(KanbanTaskDetail.self, detailJSON)

        private static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) -> Value? {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try? decoder.decode(type, from: Data(json.utf8))
        }

        private static let boardJSON = #"""
            {"assignees":["default","ops"],"latest_event_id":12,"now":1791985341,"columns":[
            {"name":"triage","tasks":[
              {"id":"t_a1","title":"Summarize the nightly build log","assignee":null,"status":"triage","priority":0}]},
            {"name":"todo","tasks":[{"id":"t_b2","title":"Rotate the gateway token","assignee":"ops","status":"todo","priority":2}]},
            {"name":"ready","tasks":[
              {"id":"t_c3","title":"Write the release notes","assignee":"default","status":"ready","priority":1},
              {"id":"t_d4","title":"Check disk use on the testbed","assignee":"ops","status":"ready","priority":0}]},
            {"name":"running","tasks":[{"id":"t_e5","title":"Index the docs folder","assignee":"default","status":"running","priority":3}]},
            {"name":"blocked","tasks":[]},
            {"name":"done","tasks":[{"id":"t_f6","title":"Set up the CI runner","assignee":"ops","status":"done","priority":0}]}
            ]}
            """#

        private static let boardsJSON = #"""
            {"boards":[{"slug":"default","name":"Default","is_current":true,"total":6},
            {"slug":"home","name":"Home","description":"Household jobs","total":2}],"current":"default"}
            """#

        private static let detailJSON = #"""
            {"task":{"id":"t_c3","title":"Write the release notes","body":"Cover the kanban and tools work.",
            "assignee":"default","status":"ready","priority":1},
            "comments":[{"author":"jt","body":"Keep it short.","created_at":1791985368}],
            "events":[{"id":1,"kind":"created","created_at":1791985368},{"id":2,"kind":"claimed","created_at":1791985400}]}
            """#
    }
#endif
