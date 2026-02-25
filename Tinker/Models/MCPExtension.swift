import Foundation

// MARK: - MCP Extension Model

struct MCPExtension: Identifiable, Codable, Hashable {
    var id: String  // key in mcpServers dict
    var name: String
    var description: String
    var type: MCPType
    var command: String?
    var args: [String]?
    var url: String?
    var env: [String: String]
    var enabled: Bool

    enum MCPType: String, Codable, Hashable {
        case stdio
        case http
        case sse
    }

    var displayType: String {
        switch type {
        case .stdio: return "Local (stdio)"
        case .http: return "Remote (HTTP)"
        case .sse: return "Remote (SSE)"
        }
    }

    /// Estimate tool count (rough heuristic)
    var estimatedToolCount: Int {
        // Most MCP servers expose 3-10 tools; we'll use 5 as a reasonable default
        5
    }
}

// MARK: - Catalog Entry (for browsable directory)

struct MCPCatalogEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol name
    let category: MCPCategory
    let type: MCPExtension.MCPType
    let command: String?
    let args: [String]?
    let url: String?
    let envKeys: [String]  // required env var names

    enum MCPCategory: String, CaseIterable {
        case search = "Search"
        case developer = "Developer"
        case data = "Data"
        case media = "Media"
        case ai = "AI"
        case productivity = "Productivity"
        case other = "Other"
    }
}

// MARK: - Built-in Catalog

extension MCPCatalogEntry {
    static let catalog: [MCPCatalogEntry] = [
        // Search
        MCPCatalogEntry(
            id: "brave-search", name: "Brave Search", description: "Web, news, image, and video search via Brave API",
            icon: "magnifyingglass", category: .search, type: .stdio,
            command: "npx", args: ["-y", "@brave/brave-search-mcp-server"], url: nil,
            envKeys: ["BRAVE_API_KEY"]
        ),
        MCPCatalogEntry(
            id: "tavily", name: "Tavily", description: "AI-optimized web search and content extraction",
            icon: "globe", category: .search, type: .stdio,
            command: "npx", args: ["-y", "tavily-mcp-server"], url: nil,
            envKeys: ["TAVILY_API_KEY"]
        ),
        MCPCatalogEntry(
            id: "fetch", name: "Fetch", description: "Fetch and extract content from URLs",
            icon: "arrow.down.doc", category: .search, type: .stdio,
            command: "uvx", args: ["mcp-server-fetch"], url: nil,
            envKeys: []
        ),

        // Developer
        MCPCatalogEntry(
            id: "github", name: "GitHub", description: "Manage repos, issues, PRs, and code search",
            icon: "chevron.left.forwardslash.chevron.right", category: .developer, type: .stdio,
            command: "npx", args: ["-y", "@modelcontextprotocol/server-github"], url: nil,
            envKeys: ["GITHUB_TOKEN"]
        ),
        MCPCatalogEntry(
            id: "filesystem", name: "Filesystem", description: "Read, write, and manage files and directories",
            icon: "folder", category: .developer, type: .stdio,
            command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/"], url: nil,
            envKeys: []
        ),
        MCPCatalogEntry(
            id: "playwright", name: "Playwright", description: "Browser automation and testing",
            icon: "globe.badge.chevron.backward", category: .developer, type: .stdio,
            command: "npx", args: ["-y", "@anthropic/mcp-playwright"], url: nil,
            envKeys: []
        ),

        // Data
        MCPCatalogEntry(
            id: "postgres", name: "PostgreSQL", description: "Query and manage PostgreSQL databases",
            icon: "cylinder", category: .data, type: .stdio,
            command: "npx", args: ["-y", "@modelcontextprotocol/server-postgres"], url: nil,
            envKeys: ["POSTGRES_URL"]
        ),
        MCPCatalogEntry(
            id: "sqlite", name: "SQLite", description: "Query local SQLite databases",
            icon: "cylinder.split.1x2", category: .data, type: .stdio,
            command: "uvx", args: ["mcp-server-sqlite"], url: nil,
            envKeys: []
        ),
        MCPCatalogEntry(
            id: "supabase", name: "Supabase", description: "Manage Supabase projects, databases, and auth",
            icon: "bolt", category: .data, type: .http,
            command: nil, args: nil, url: "https://mcp.supabase.com/mcp",
            envKeys: ["SUPABASE_ACCESS_TOKEN"]
        ),

        // Media
        MCPCatalogEntry(
            id: "elevenlabs", name: "ElevenLabs", description: "Text-to-speech, voice cloning, and audio generation",
            icon: "waveform", category: .media, type: .stdio,
            command: "uvx", args: ["elevenlabs-mcp"], url: nil,
            envKeys: ["ELEVENLABS_API_KEY"]
        ),

        // AI
        MCPCatalogEntry(
            id: "deepseek", name: "DeepSeek", description: "DeepSeek chat and reasoning as a thinking partner",
            icon: "brain", category: .ai, type: .stdio,
            command: "npx", args: ["-y", "deepseek-mcp-server"], url: nil,
            envKeys: ["DEEPSEEK_API_KEY"]
        ),
        MCPCatalogEntry(
            id: "mcp-knowledge-graph", name: "Knowledge Graph", description: "Persistent memory via entity-relationship graph",
            icon: "point.3.connected.trianglepath.dotted", category: .ai, type: .stdio,
            command: "npx", args: ["-y", "mcp-knowledge-graph"], url: nil,
            envKeys: []
        ),

        // Productivity
        MCPCatalogEntry(
            id: "linear", name: "Linear", description: "Manage issues, projects, and cycles in Linear",
            icon: "checkmark.circle", category: .productivity, type: .http,
            command: nil, args: nil, url: "https://mcp.linear.app/mcp",
            envKeys: []
        ),
        MCPCatalogEntry(
            id: "notion", name: "Notion", description: "Search, create, and manage Notion pages and databases",
            icon: "doc.text", category: .productivity, type: .stdio,
            command: "npx", args: ["-y", "@notionhq/notion-mcp-server"], url: nil,
            envKeys: ["NOTION_API_KEY"]
        ),
        MCPCatalogEntry(
            id: "slack", name: "Slack", description: "Read and send messages in Slack workspaces",
            icon: "number", category: .productivity, type: .stdio,
            command: "npx", args: ["-y", "@anthropic/mcp-slack"], url: nil,
            envKeys: ["SLACK_BOT_TOKEN"]
        ),
    ]

    static func find(_ id: String) -> MCPCatalogEntry? {
        catalog.first { $0.id == id }
    }
}
