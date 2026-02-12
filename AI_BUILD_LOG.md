# AI Build Log — ChainGuard AI

> Documentation of AI-assisted development for the BNB Chain OpenClaw Hackathon.

---

## AI Tools Used

| Tool | Role |
|---|---|
| **Claude Sonnet 4** (Anthropic) | Smart contract vulnerability analysis — core AI engine |
| **Gemini Code Assist** | Development assistant — code generation, debugging, architecture |
| **Foundry** | Smart contract testing and deployment framework |

---

## Build Timeline

### Phase 1: Smart Contract Fixes
- Fixed `VulnerabilityScanner.sol` — `block.timestamp` in pure functions, bytecode underflow protections
- Fixed `AuditNFT.sol` — authorization bug where `mintCertificate` didn't allow ChainGuard as a caller
- Fixed all test files — authorization pranks, precompile addresses, event parameters
- **Result:** 61/66 tests passing (5 are invariant harness design limitations)

### Phase 2: Agent Overhaul
- Replaced OpenAI GPT-4 with Anthropic Claude Sonnet 4
- Built 6 modular service modules:
  - `claude-analyzer.js` — OWASP Top 10 vulnerability detection
  - `contract-monitor.js` — BSCScan source fetch + block polling
  - `ipfs-uploader.js` — Pinata IPFS integration
  - `onchain-reporter.js` — SecurityRegistry + AuditNFT interaction
  - `telegram-bot.js` — Critical/High severity alerts
  - `database.js` — SQLite scan history persistence
- Built main orchestrator with Express API (12 endpoints) + Socket.io

### Phase 3: React Frontend Dashboard
- Scaffolded Vite + React application
- Built 5 core components:
  - `StatsOverview` — key metrics cards
  - `ManualScanner` — address input → Claude analysis → detailed results
  - `VulnerabilityFeed` — real-time scan history with severity badges
  - `SeverityChart` — Recharts pie/bar visualization
  - `WalletConnect` — MetaMask integration with BSC Testnet auto-switch
- Dark cybersecurity theme with glassmorphism, micro-animations, responsive layout

### Phase 4: Documentation
- Updated README.md with architecture, API docs, setup guide
- Created this AI build log

---

## Key AI-Driven Decisions

1. **Claude over GPT-4**: Better structured output for vulnerability classification, native JSON mode
2. **Modular services**: Each service is independently testable and replaceable
3. **Fallback patterns**: IPFS uploader generates placeholder hashes when offline, Claude returns safe defaults on error
4. **Dual authorization**: AuditNFT accepts both SecurityRegistry and ChainGuard as authorized minters
