# Graph Report - godot-mcp  (2026-10-27)

## Corpus Check
- Corpus is ~9,134 words - fits in a single context window. You may not need a graph.

## Summary
- 165 nodes · 296 edges · 8 communities (6 shown, 2 thin omitted)
- Extraction: 91% EXTRACTED · 8% INFERRED · 1% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.83)
- Token cost: 74,136 input · 0 output

## Community Hubs (Navigation)
- Contributor Workflow
- NPM Package Manifest
- GodotServer Tool Handlers
- Node Runtime Imports
- TypeScript Build Config
- Funding Links
- Scene Operations Script
- Issue Reporting

## God Nodes (most connected - your core abstractions)
1. `GodotServer` - 35 edges
2. `Godot MCP Server` - 17 edges
3. `compilerOptions` - 12 edges
4. `execFileAsync` - 7 edges
5. `godot_operations.gd bundled operations script` - 7 edges
6. `Adding New Tools` - 7 edges
7. `Scene Management` - 6 edges
8. `scripts` - 5 edges
9. `@coding-solo/godot-mcp npm package` - 5 edges
10. `autoApprove tool list` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Project Structure` --references--> `GodotServer`  [INFERRED]
  CONTRIBUTING.md → src/index.ts
- `capture_screenshot tool` --semantically_similar_to--> `get_debug_output tool`  [INFERRED] [semantically similar]
  CONTRIBUTING.md → README.md
- `capture_screenshot tool` --references--> `autoApprove tool list`  [AMBIGUOUS]
  CONTRIBUTING.md → README.md
- `Development Environment Setup` --semantically_similar_to--> `Building from Source`  [INFERRED] [semantically similar]
  CONTRIBUTING.md → README.md
- `capture_screenshot tool` --conceptually_related_to--> `run_project tool`  [INFERRED]
  CONTRIBUTING.md → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Scene operations routed through godot_operations.gd** — readme_bundled_operations_script, readme_create_scene, readme_add_node, readme_load_sprite, readme_export_mesh_library, readme_save_scene [INFERRED 0.75]
- **Run / observe / stop execution feedback loop** — readme_run_project, readme_get_debug_output, readme_stop_project, readme_agent_feedback_loop [INFERRED 0.85]
- **New MCP tool addition workflow** — contributing_adding_new_tools, contributing_setuptoolhandlers, contributing_createerrorresponse, readme_autoapprove, contributing_testing [EXTRACTED 1.00]

## Communities (8 total, 2 thin omitted)

### Community 0 - "Contributor Workflow"
Cohesion: 0.07
Nodes (36): Adding New Tools, capture_screenshot tool, Code of Conduct, createErrorResponse helper, Debugging the MCP Server, Development Environment Setup, Documentation Guidelines, MCP Inspector (+28 more)

### Community 1 - "NPM Package Manifest"
Cohesion: 0.06
Nodes (35): author, bin, godot-mcp, bugs, url, dependencies, axios@^1.7.9, fs-extra@^11.2.0 (+27 more)

### Community 3 - "Node Runtime Imports"
Cohesion: 0.14
Nodes (8): __dirname, __filename, __dirname, __filename, GodotProcess, GodotServerConfig, OperationParams, server

### Community 4 - "TypeScript Build Config"
Cohesion: 0.13
Nodes (14): compilerOptions, allowJs, esModuleInterop, forceConsistentCasingInFileNames, module, moduleResolution, outDir, resolveJsonModule (+6 more)

### Community 5 - "Funding Links"
Cohesion: 0.14
Nodes (13): buy_me_a_coffee, community_bridge, custom, github, issuehunt, ko_fi, lfx_crowdfunding, liberapay (+5 more)

### Community 6 - "Scene Operations Script"
Cohesion: 0.48
Nodes (6): add_node tool, create_scene tool, export_mesh_library tool, load_sprite tool, save_scene tool, Scene Management

## Ambiguous Edges - Review These
- `update_project_uids tool` → `godot_operations.gd bundled operations script`  [AMBIGUOUS]
  README.md · relation: calls
- `autoApprove tool list` → `capture_screenshot tool`  [AMBIGUOUS]
  CONTRIBUTING.md · relation: references

## Knowledge Gaps
- **9 isolated node(s):** `Model Context Protocol (MCP)`, `get_godot_version tool`, `get_uid tool`, `Code of Conduct`, `Reporting Bugs` (+4 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 66 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GodotServer` connect `GodotServer Tool Handlers` to `Contributor Workflow`, `Node Runtime Imports`?**
  _High betweenness centrality (0.438) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `godot_operations.gd bundled operations script` (e.g. with `export_mesh_library tool` and `load_sprite tool`) actually correct?**
  _`godot_operations.gd bundled operations script` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Model Context Protocol (MCP)`, `get_godot_version tool`, `get_uid tool` to the rest of the system?**
  _9 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Contributor Workflow` be split into smaller, more focused modules?**
  _Cohesion score 0.07073170731707316 - nodes in this community are weakly interconnected._
- **Why does `Godot MCP Server` connect `Contributor Workflow` to `Scene Operations Script`?**
  _High betweenness centrality (0.337) - this node is a cross-community bridge._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `update_project_uids tool` and `godot_operations.gd bundled operations script`?**
  _Edge tagged AMBIGUOUS (relation: calls) - confidence is low._
- **What is the exact relationship between `autoApprove tool list` and `capture_screenshot tool`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._