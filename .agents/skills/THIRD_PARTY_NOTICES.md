# Third-party skills

These agent skills are vendored, unmodified, from the repositories below. Each skill folder keeps its upstream MIT license in `LICENSE`. All scripts were read before vendoring (2026-10-31). To update a skill, copy it again from upstream, read the diff, and bump the commit here.

| Skill | Source | Commit | License |
|---|---|---|---|
| `app-store-changelog`, `ios-debugger-agent`, `review-swarm`, `swift-concurrency-expert`, `swiftui-liquid-glass`, `swiftui-performance-audit`, `swiftui-ui-patterns`, `swiftui-view-refactor` | [Dimillian/Skills](https://github.com/Dimillian/Skills) | `05ba982bfeb0d77d3c97d4542b0ee15034d05f84` | MIT © 2026 Thomas Ricouard |
| `ios-app-intents`, `ios-ettrace-performance`, `ios-memgraph-leaks` | [openai/plugins](https://github.com/openai/plugins) `plugins/build-ios-apps` | `0722921d5542fc593105c27bd52630babd8b8c2a` | MIT (declared in the plugin manifest), © OpenAI |
| `swiftui-expert-skill` | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) | `204dba7c67256a8b707ee3fbc5759a824191974f` | MIT © 2026 Antoine van der Lee |
| `swiftui-pro` | [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) | `f2920b63995263f57b3e198674e89a602efba6d2` | MIT © 2026 Paul Hudson |

Not vendored:
- `ios-simulator-browser` (openai/plugins) runs `npx --yes serve-sim@latest`, an unpinned package executed at runtime.
- OpenAI's copies of the `swiftui-*` and `ios-debugger-agent` skills, which duplicate Dimillian's with shorter descriptions.

Tools these skills ask for at use time, installed only with the developer's approval:
- `ios-ettrace-performance`: `brew install emergetools/homebrew-tap/ettrace`.
- `ios-debugger-agent`: the XcodeBuildMCP server. Pin a version (for example `npx -y xcodebuildmcp@2.7.0 mcp`), never `@latest`.
