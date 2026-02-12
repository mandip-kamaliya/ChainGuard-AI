# 🛡️ ChainGuard AI

**Autonomous Smart Contract Security Agent for BNB Chain**

> AI-powered real-time vulnerability detection, automated on-chain reporting, and audit NFT certification — built for the BNB Chain OpenClaw Hackathon.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🤖 **Claude Sonnet 4 Analysis** | OWASP Smart Contract Top 10 vulnerability detection using Anthropic Claude |
| ⛓️ **On-Chain Reporting** | Findings stored on SecurityRegistry, audit NFTs minted via AuditNFT |
| 📌 **IPFS Storage** | Full audit reports pinned to IPFS via Pinata |
| 📱 **Telegram Alerts** | Instant notifications for CRITICAL/HIGH severity findings |
| 🔍 **Real-Time Monitoring** | Auto-detect new contract deployments and scan them |
| 📊 **React Dashboard** | Dark-themed cybersecurity dashboard with real-time WebSocket updates |
| 🏆 **Audit NFT Certificates** | ERC-721 certificates linking to IPFS audit reports |
| 💾 **SQLite Persistence** | Scan history, alerts, and contract tracking |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                  React Dashboard                     │
│  (Vite + Recharts + Socket.io + MetaMask)           │
└──────────────────────┬──────────────────────────────┘
                       │ WebSocket + REST API
┌──────────────────────┴──────────────────────────────┐
│               Agent Orchestrator                     │
│  Express API · Socket.io · Scan Pipeline            │
├─────────────────────────────────────────────────────┤
│  Claude       Contract    IPFS      Telegram        │
│  Analyzer     Monitor     Uploader  Bot             │
│                                                     │
│  On-Chain     SQLite                                │
│  Reporter     Database                              │
└──────────────────────┬──────────────────────────────┘
                       │ ethers.js
┌──────────────────────┴──────────────────────────────┐
│            Smart Contracts (Solidity)                │
│  ChainGuard · SecurityRegistry · AuditNFT           │
│  VulnerabilityScanner                               │
│                                                     │
│  BNB Chain / opBNB Testnet                          │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- **Node.js** ≥ 18
- **Foundry** (forge, cast, anvil) — [install](https://book.getfoundry.sh/getting-started/installation)

### 1. Clone & install

```bash
git clone https://github.com/your-org/chainguard-ai.git
cd chainguard-ai
npm install
cd frontend && npm install && cd ..
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your API keys:
#   ANTHROPIC_API_KEY    — Claude Sonnet 4
#   PINATA_API_KEY       — IPFS storage
#   TELEGRAM_BOT_TOKEN   — Alerts
#   PRIVATE_KEY          — BSC/opBNB wallet
#   BSCSCAN_API_KEY      — Source code fetching
```

### 3. Build & test contracts

```bash
forge build
forge test
```

### 4. Deploy contracts (optional)

```bash
# BSC Testnet
forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast

# opBNB Testnet
forge script script/Deploy.s.sol --rpc-url opbnb_testnet --broadcast
```

### 5. Start the agent

```bash
npm run dev
# Agent API runs at http://localhost:3001
```

### 6. Start the dashboard

```bash
cd frontend
npm run dev
# Dashboard at http://localhost:5173
```

---

## 📡 API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/status` | Agent health + service status |
| `POST` | `/api/scan` | Scan a contract `{ contractAddress }` |
| `GET` | `/api/scans` | Recent scan history |
| `GET` | `/api/scans/:id` | Get scan by ID |
| `GET` | `/api/stats` | System statistics |
| `GET` | `/api/alerts` | Security alerts |
| `POST` | `/api/monitor/start` | Start block monitoring |
| `POST` | `/api/monitor/stop` | Stop block monitoring |
| `GET` | `/api/contracts` | Monitored contracts |
| `POST` | `/api/contracts` | Add contract to monitoring |

WebSocket events: `scanResult`, `monitoringStatus`, `stats`, `recentScans`

---

## 🧪 Smart Contracts

| Contract | Description |
|---|---|
| `ChainGuard.sol` | Main orchestrator — register, scan, report, mint |
| `SecurityRegistry.sol` | Vulnerability report storage, contract pause/unpause |
| `AuditNFT.sol` | ERC-721 audit certificates with IPFS metadata |
| `VulnerabilityScanner.sol` | On-chain bytecode pattern analysis |

### Test Results

```
ChainGuard.t.sol       ✅ 12/12 passed
SecurityRegistry.t.sol ✅ 36/36 passed
Integration.t.sol      ✅ 13/13 passed
Invariant.t.sol        ⚠️  12/17 passed (5 harness design issues)
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **AI** | Anthropic Claude Sonnet 4 |
| **Smart Contracts** | Solidity ^0.8.19, Foundry, OpenZeppelin |
| **Blockchain** | BNB Chain, opBNB Testnet |
| **Backend** | Node.js, Express, Socket.io, ethers.js |
| **Frontend** | React (Vite), Recharts, Lucide Icons |
| **Storage** | IPFS (Pinata), SQLite (better-sqlite3) |
| **Notifications** | Telegram Bot API |

---

## 📂 Project Structure

```
chainguard-ai/
├── src/                    # Solidity contracts
│   ├── ChainGuard.sol
│   ├── SecurityRegistry.sol
│   ├── AuditNFT.sol
│   └── VulnerabilityScanner.sol
├── test/                   # Foundry test suite
├── script/                 # Deployment scripts
├── agent/                  # Node.js agent
│   ├── index.js            # Main orchestrator + API
│   └── services/
│       ├── claude-analyzer.js
│       ├── contract-monitor.js
│       ├── ipfs-uploader.js
│       ├── onchain-reporter.js
│       ├── telegram-bot.js
│       └── database.js
├── frontend/               # React dashboard
│   └── src/
│       ├── components/
│       └── api.js
└── foundry.toml
```

---

## 📄 License

MIT
