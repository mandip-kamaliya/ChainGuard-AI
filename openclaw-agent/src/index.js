import Anthropic from "@anthropic-ai/sdk";
import { Web3 } from "web3";
import TelegramBot from "node-telegram-bot-api";
import { ContractMonitor } from "./monitors/ContractMonitor.js";
import { VulnerabilityAnalyzer } from "./analyzers/VulnerabilityAnalyzer.js";
import { OnchainReporter } from "./reporters/OnchainReporter.js";
import { IPFSUploader } from "./storage/IPFSUploader.js";
import dotenv from "dotenv";

dotenv.config();

class ChainGuardAgent {
    constructor() {
        // ─── AI Engine ───
        this.anthropic = new Anthropic({
            apiKey: process.env.ANTHROPIC_API_KEY,
        });

        // ─── Blockchain Providers ───
        this.web3BSC = new Web3(
            process.env.BSC_TESTNET_RPC_URL ||
            "https://data-seed-prebsc-1-s1.binance.org:8545/"
        );
        this.web3opBNB = new Web3(
            process.env.OPBNB_TESTNET_RPC_URL ||
            "https://opbnb-testnet-rpc.bnbchain.org"
        );

        // ─── Telegram Bot ───
        this.telegram = process.env.TELEGRAM_BOT_TOKEN
            ? new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: true })
            : null;

        // ─── Service Modules ───
        this.monitor = new ContractMonitor(this.web3BSC, this.web3opBNB);
        this.analyzer = new VulnerabilityAnalyzer(this.anthropic);
        this.reporter = new OnchainReporter(this.web3BSC);
        this.ipfs = new IPFSUploader();

        this.isRunning = false;
        this.scanCount = 0;
        this.vulnCount = 0;
        this.criticalCount = 0;
    }

    async start() {
        console.log("");
        console.log("╔════════════════════════════════════════════════╗");
        console.log("║     🛡️  ChainGuard AI — OpenClaw Agent         ║");
        console.log("╠════════════════════════════════════════════════╣");
        console.log(
            `║  📡 BSC:    ${(process.env.BSC_TESTNET_RPC_URL || "default").slice(0, 35).padEnd(35)}║`
        );
        console.log(
            `║  📡 opBNB:  ${(process.env.OPBNB_TESTNET_RPC_URL || "default").slice(0, 35).padEnd(35)}║`
        );
        console.log(
            `║  🤖 AI:     Claude Sonnet 4                   ║`
        );
        console.log(
            `║  📱 Telegram: ${this.telegram ? "Enabled" : "Disabled"}                           ║`
        );
        console.log("╚════════════════════════════════════════════════╝");
        console.log("");

        this.isRunning = true;

        // ─── Verify connections ───
        try {
            const bscBlock = await this.web3BSC.eth.getBlockNumber();
            console.log(`✅ BSC Testnet connected — block #${bscBlock}`);
        } catch (err) {
            console.error("❌ BSC Testnet connection failed:", err.message);
        }

        try {
            const opbnbBlock = await this.web3opBNB.eth.getBlockNumber();
            console.log(`✅ opBNB Testnet connected — block #${opbnbBlock}`);
        } catch (err) {
            console.warn("⚠️  opBNB Testnet connection failed:", err.message);
        }

        // ─── Start autonomous monitoring ───
        await this.monitor.startMonitoring(async (contractData) => {
            await this.handleNewContract(contractData);
        });

        // ─── Setup Telegram commands ───
        if (this.telegram) {
            this.setupTelegramBot();
        }

        console.log("\n✅ Agent is now running autonomously!\n");
        console.log("Listening for new contract deployments...\n");
    }

    /**
     * Core pipeline: detect → analyze → upload → report → alert
     */
    async handleNewContract(contractData) {
        const { address, code, network } = contractData;

        console.log(`\n${"─".repeat(60)}`);
        console.log(`🔍 New contract detected on ${network}: ${address}`);
        console.log(`   Code size: ${code ? (code.length - 2) / 2 : 0} bytes`);

        const startTime = Date.now();

        try {
            // ── Step 1: Analyze with Claude ──
            console.log("🤖 Running Claude vulnerability analysis...");
            const vulnerabilities = await this.analyzer.analyze(code, address);
            this.scanCount++;

            if (vulnerabilities.length === 0) {
                console.log("✅ No vulnerabilities found");
                console.log(
                    `   Completed in ${Date.now() - startTime}ms`
                );
                return;
            }

            const counts = this.countBySeverity(vulnerabilities);
            this.vulnCount += vulnerabilities.length;
            this.criticalCount += counts.critical;

            console.log(
                `⚠️  Found ${vulnerabilities.length} vulnerabilities:`
            );
            console.log(
                `   🔴 ${counts.critical} critical · 🟠 ${counts.high} high · 🟡 ${counts.medium} medium · 🟢 ${counts.low} low`
            );

            // ── Step 2: Upload report to IPFS ──
            console.log("📌 Uploading report to IPFS...");
            const ipfsHash = await this.ipfs.upload({
                contract: address,
                network,
                vulnerabilities,
                scanTimestamp: new Date().toISOString(),
                agent: "ChainGuard AI v1.0.0",
            });

            console.log(`📦 Report pinned to IPFS: ${ipfsHash}`);

            // ── Step 3: Submit report on-chain ──
            let txHash = null;
            try {
                console.log("⛓️  Submitting report on-chain...");
                txHash = await this.reporter.submitReport(
                    address,
                    ipfsHash,
                    counts
                );
                console.log(`✅ On-chain report tx: ${txHash}`);
            } catch (err) {
                console.warn(
                    "⚠️  On-chain report skipped:",
                    err.message
                );
            }

            // ── Step 4: Telegram alert for critical/high ──
            if (counts.critical > 0 && this.telegram) {
                await this.sendTelegramAlert(
                    address,
                    vulnerabilities.filter(
                        (v) => v.severity === "CRITICAL"
                    ),
                    txHash,
                    ipfsHash
                );
            }

            console.log(
                `\n✅ Scan complete in ${Date.now() - startTime}ms`
            );
        } catch (error) {
            console.error(
                `❌ Error processing ${address}:`,
                error.message
            );
        }
    }

    /**
     * Count vulnerabilities by severity
     */
    countBySeverity(vulnerabilities) {
        return {
            critical: vulnerabilities.filter(
                (v) => v.severity === "CRITICAL"
            ).length,
            high: vulnerabilities.filter((v) => v.severity === "HIGH")
                .length,
            medium: vulnerabilities.filter(
                (v) => v.severity === "MEDIUM"
            ).length,
            low: vulnerabilities.filter((v) => v.severity === "LOW")
                .length,
        };
    }

    /**
     * Send critical vulnerability alert to Telegram
     */
    async sendTelegramAlert(
        contractAddress,
        vulnerabilities,
        txHash,
        ipfsHash
    ) {
        if (!this.telegram) return;

        const message = [
            "🚨 *CRITICAL VULNERABILITIES DETECTED* 🚨",
            "",
            `*Contract:* \`${contractAddress}\``,
            `*Issues Found:* ${vulnerabilities.length}`,
            "",
            ...vulnerabilities.map(
                (v, i) => `${i + 1}. *[${v.severity}]* ${v.title}`
            ),
            "",
            txHash ? `⛓️ [View on BscScan](https://testnet.bscscan.com/tx/${txHash})` : "",
            ipfsHash ? `📋 [Full Report](https://gateway.pinata.cloud/ipfs/${ipfsHash})` : "",
            "",
            `⏰ ${new Date().toISOString()}`,
        ]
            .filter(Boolean)
            .join("\n");

        try {
            await this.telegram.sendMessage(
                process.env.TELEGRAM_CHAT_ID,
                message,
                { parse_mode: "Markdown", disable_web_page_preview: true }
            );
            console.log("📱 Telegram alert sent");
        } catch (err) {
            console.error("📱 Telegram send failed:", err.message);
        }
    }

    /**
     * Setup Telegram bot commands
     */
    setupTelegramBot() {
        // /scan <address> — Manual contract scan
        this.telegram.onText(/\/scan (.+)/, async (msg, match) => {
            const chatId = msg.chat.id;
            const contractAddress = match[1].trim();

            if (
                !contractAddress.startsWith("0x") ||
                contractAddress.length !== 42
            ) {
                await this.telegram.sendMessage(
                    chatId,
                    "❌ Invalid contract address. Use: /scan 0x..."
                );
                return;
            }

            await this.telegram.sendMessage(
                chatId,
                `🔍 Scanning \`${contractAddress}\`...`,
                { parse_mode: "Markdown" }
            );

            try {
                const code = await this.web3BSC.eth.getCode(
                    contractAddress
                );

                if (code === "0x" || !code) {
                    await this.telegram.sendMessage(
                        chatId,
                        "❌ No contract code found at this address."
                    );
                    return;
                }

                await this.handleNewContract({
                    address: contractAddress,
                    code,
                    network: "BSC Testnet",
                });

                await this.telegram.sendMessage(
                    chatId,
                    "✅ Scan complete! Check results above."
                );
            } catch (error) {
                await this.telegram.sendMessage(
                    chatId,
                    `❌ Error: ${error.message}`
                );
            }
        });

        // /stats — Agent statistics
        this.telegram.onText(/\/stats/, async (msg) => {
            const stats = this.getStats();
            await this.telegram.sendMessage(msg.chat.id, stats, {
                parse_mode: "Markdown",
            });
        });

        // /status — Agent status
        this.telegram.onText(/\/status/, async (msg) => {
            const status = [
                "🛡️ *ChainGuard AI Status*",
                "",
                `🟢 Agent: ${this.isRunning ? "Running" : "Stopped"}`,
                `🔍 Monitoring: ${this.monitor.isMonitoring ? "Active" : "Inactive"}`,
                `📡 BSC: Connected`,
                `⏰ Uptime: ${this.getUptime()}`,
            ].join("\n");

            await this.telegram.sendMessage(msg.chat.id, status, {
                parse_mode: "Markdown",
            });
        });

        // /help — Show available commands
        this.telegram.onText(/\/help|\/start/, async (msg) => {
            const help = [
                "🛡️ *ChainGuard AI Commands*",
                "",
                "/scan `<address>` — Scan a contract for vulnerabilities",
                "/stats — View agent statistics",
                "/status — Check agent status",
                "/help — Show this help message",
            ].join("\n");

            await this.telegram.sendMessage(msg.chat.id, help, {
                parse_mode: "Markdown",
            });
        });

        console.log("📱 Telegram bot commands registered");
    }

    /**
     * Get formatted stats string
     */
    getStats() {
        const dbStats = this.monitor.getStats();

        return [
            "📊 *ChainGuard AI Statistics*",
            "",
            `🔍 Contracts Scanned: ${this.scanCount}`,
            `⚠️  Vulnerabilities Found: ${this.vulnCount}`,
            `🔴 Critical Issues: ${this.criticalCount}`,
            `📋 Contracts Monitored: ${dbStats.monitoredCount}`,
            `🕐 Last Scan: ${dbStats.lastScanTime || "N/A"}`,
            "",
            `⏰ Report generated: ${new Date().toISOString()}`,
        ].join("\n");
    }

    /**
     * Get uptime string
     */
    getUptime() {
        const uptime = process.uptime();
        const hours = Math.floor(uptime / 3600);
        const mins = Math.floor((uptime % 3600) / 60);
        const secs = Math.floor(uptime % 60);
        return `${hours}h ${mins}m ${secs}s`;
    }

    async stop() {
        console.log("\n🛑 Stopping ChainGuard AI Agent...");
        this.isRunning = false;
        await this.monitor.stopMonitoring();
        if (this.telegram) {
            this.telegram.stopPolling();
        }
        console.log("👋 Agent stopped. Goodbye!");
    }
}

// ─── Start the agent ───
const agent = new ChainGuardAgent();
agent.start().catch(console.error);

// ─── Graceful shutdown ───
process.on("SIGINT", async () => {
    await agent.stop();
    process.exit(0);
});

process.on("SIGTERM", async () => {
    await agent.stop();
    process.exit(0);
});

process.on("unhandledRejection", (reason) => {
    console.error("Unhandled rejection:", reason);
});
