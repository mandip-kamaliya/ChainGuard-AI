/**
 * ContractMonitor — Real-time contract deployment monitoring
 *
 * Watches for new contract deployments on BSC and opBNB testnets.
 * Fetches source code from BSCScan API, queues contracts for analysis,
 * and persists scan status in a JSON file (fallback for SQLite issues).
 */

import axios from "axios";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export class ContractMonitor {
    constructor(web3BSC, web3opBNB) {
        this.web3BSC = web3BSC;
        this.web3opBNB = web3opBNB;
        this.isMonitoring = false;
        this.pollingInterval = null;
        this.callback = null;

        // ─── Rate limiting ───
        this.requestQueue = [];
        this.isProcessing = false;
        this.rateLimitDelay = 250; // 250ms between API calls
        this.lastBscScanCall = 0;

        // ─── BSCScan API ───
        this.bscscanApiKey = process.env.BSCSCAN_API_KEY || "";
        this.bscscanEndpoints = {
            BSC: "https://api-testnet.bscscan.com/api",
            opBNB: "https://api-opbnb-testnet.bscscan.com/api",
        };

        // ─── JSON Database (Simple file persistence) ───
        this.dbPath = path.join(__dirname, "..", "..", "data", "contracts.json");
        this.data = this.loadDatabase();
    }

    /**
     * Initialize/Load JSON database
     */
    loadDatabase() {
        const dataDir = path.dirname(this.dbPath);
        if (!fs.existsSync(dataDir)) {
            fs.mkdirSync(dataDir, { recursive: true });
        }

        if (!fs.existsSync(this.dbPath)) {
            const initialData = {
                contracts: {}, // Map address -> Contract object
                scanLog: [],
                lastScan: null
            };
            this.saveDatabase(initialData);
            return initialData;
        }

        try {
            return JSON.parse(fs.readFileSync(this.dbPath, "utf8"));
        } catch (err) {
            console.error("Failed to load DB, resetting:", err.message);
            return { contracts: {}, scanLog: [], lastScan: null };
        }
    }

    saveDatabase(data = this.data) {
        try {
            fs.writeFileSync(this.dbPath, JSON.stringify(data, null, 2));
        } catch (err) {
            console.error("Failed to save DB:", err.message);
        }
    }

    /**
     * Start monitoring for new contract deployments
     * @param {function} callback - Called with { address, code, network }
     */
    async startMonitoring(callback) {
        if (this.isMonitoring) {
            console.log("⚠️  Already monitoring");
            return;
        }

        this.isMonitoring = true;
        this.callback = callback;

        console.log("🔍 Starting contract deployment monitoring...");

        // Track last processed block per network
        let lastBscBlock;
        let lastOpbnbBlock;

        try {
            lastBscBlock = Number(await this.web3BSC.eth.getBlockNumber());
            console.log(`   BSC starting at block #${lastBscBlock}`);
        } catch (err) {
            console.error("   BSC block fetch failed:", err.message);
            lastBscBlock = 0;
        }

        try {
            lastOpbnbBlock = Number(await this.web3opBNB.eth.getBlockNumber());
            console.log(`   opBNB starting at block #${lastOpbnbBlock}`);
        } catch (err) {
            console.warn("   opBNB block fetch failed:", err.message);
            lastOpbnbBlock = 0;
        }

        // ─── Poll for new blocks every 10 seconds ───
        this.pollingInterval = setInterval(async () => {
            if (!this.isMonitoring) return;

            // BSC Testnet
            try {
                const currentBlock = Number(
                    await this.web3BSC.eth.getBlockNumber()
                );

                for (
                    let blockNum = lastBscBlock + 1;
                    blockNum <= currentBlock;
                    blockNum++
                ) {
                    await this.processBlock(
                        this.web3BSC,
                        blockNum,
                        "BSC Testnet"
                    );
                }

                lastBscBlock = currentBlock;
            } catch (err) {
                // Suppress frequent polling errors
                if (!err.message.includes("rate")) {
                    console.error(
                        "BSC polling error:",
                        err.message.slice(0, 80)
                    );
                }
            }

            // opBNB Testnet
            if (lastOpbnbBlock > 0) {
                try {
                    const currentBlock = Number(
                        await this.web3opBNB.eth.getBlockNumber()
                    );

                    for (
                        let blockNum = lastOpbnbBlock + 1;
                        blockNum <= currentBlock;
                        blockNum++
                    ) {
                        await this.processBlock(
                            this.web3opBNB,
                            blockNum,
                            "opBNB Testnet"
                        );
                    }

                    lastOpbnbBlock = currentBlock;
                } catch {
                    // opBNB is optional, suppress errors
                }
            }
        }, 10000); // 10 second polling
    }

    /**
     * Process a single block for contract deployments
     */
    async processBlock(web3, blockNumber, network) {
        try {
            const block = await web3.eth.getBlock(blockNumber, true);
            if (!block || !block.transactions) return;

            for (const tx of block.transactions) {
                // Contract creation: tx.to is null
                if (tx.to === null || tx.to === undefined) {
                    const receipt = await web3.eth.getTransactionReceipt(
                        tx.hash
                    );

                    if (receipt && receipt.contractAddress) {
                        const contractAddress = receipt.contractAddress;

                        // Skip if already processed
                        if (this.isAlreadyScanned(contractAddress)) continue;

                        // Get contract code
                        const code = await web3.eth.getCode(contractAddress);
                        if (!code || code === "0x") continue;

                        // Record in database
                        this.recordContract(
                            contractAddress,
                            network,
                            tx.from,
                            blockNumber,
                            code
                        );

                        this.logAction(
                            contractAddress,
                            "detected",
                            `New deployment on ${network}, block #${blockNumber}`
                        );

                        console.log(
                            `🆕 New contract: ${contractAddress} on ${network} (block #${blockNumber})`
                        );

                        // Fetch source code from BSCScan (may not be verified yet)
                        let sourceCode = null;
                        try {
                            sourceCode = await this.fetchSourceCode(
                                contractAddress,
                                network.includes("opBNB")
                                    ? "opBNB"
                                    : "BSC"
                            );
                        } catch {
                            // Source may not be available
                        }

                        // Queue for analysis
                        if (this.callback) {
                            await this.callback({
                                address: contractAddress,
                                code: sourceCode || code.slice(0, 10000), // Trim large bytecode
                                network,
                            });
                        }
                    }
                }
            }
        } catch (err) {
            // Silently handle block processing errors
            if (err.message && !err.message.includes("rate")) {
                console.error(
                    `Block ${blockNumber} error:`,
                    err.message.slice(0, 60)
                );
            }
        }
    }

    /**
     * Fetch verified source code from BSCScan API
     * @param {string} address - Contract address
     * @param {string} network - 'BSC' or 'opBNB'
     * @returns {string|null} Source code
     */
    async fetchSourceCode(address, network = "BSC") {
        // Rate limiting
        const now = Date.now();
        const elapsed = now - this.lastBscScanCall;
        if (elapsed < this.rateLimitDelay) {
            await this.sleep(this.rateLimitDelay - elapsed);
        }
        this.lastBscScanCall = Date.now();

        const endpoint = this.bscscanEndpoints[network];
        if (!endpoint) return null;

        try {
            const { data } = await axios.get(endpoint, {
                params: {
                    module: "contract",
                    action: "getsourcecode",
                    address,
                    apikey: this.bscscanApiKey,
                },
                timeout: 10000,
            });

            if (
                data.result?.[0]?.SourceCode &&
                data.result[0].SourceCode !== ""
            ) {
                this.updateSourceAvailable(address, true);

                this.logAction(
                    address,
                    "source_fetched",
                    `Verified source from ${network}Scan`
                );

                return data.result[0].SourceCode;
            }

            return null;
        } catch (err) {
            console.warn(
                `BSCScan API error for ${address.slice(0, 10)}...: ${err.message}`
            );
            return null;
        }
    }

    // ─── Database Operations (JSON Impl) ───

    isAlreadyScanned(address) {
        return !!this.data.contracts[address.toLowerCase()];
    }

    recordContract(address, network, deployer, blockNumber, code) {
        const codeHash = this.hashCode(code);
        this.data.contracts[address.toLowerCase()] = {
            address: address.toLowerCase(),
            network,
            deployer,
            blockNumber,
            codeHash,
            sourceAvailable: false,
            scanStatus: 'pending',
            vulnerabilitiesFound: 0,
            ipfsHash: null,
            txHash: null,
            createdAt: new Date().toISOString(),
            scannedAt: null
        };
        this.saveDatabase();
    }

    updateScanStatus(address, status, vulnCount = 0, ipfsHash = null, txHash = null) {
        const addr = address.toLowerCase();
        if (this.data.contracts[addr]) {
            const contract = this.data.contracts[addr];
            contract.scanStatus = status;
            contract.vulnerabilitiesFound = vulnCount;
            if (ipfsHash) contract.ipfsHash = ipfsHash;
            if (txHash) contract.txHash = txHash;
            contract.scannedAt = new Date().toISOString();
            this.data.lastScan = contract.scannedAt;
            this.saveDatabase();
        }
    }

    updateSourceAvailable(address, available) {
        const addr = address.toLowerCase();
        if (this.data.contracts[addr]) {
            this.data.contracts[addr].sourceAvailable = !!available;
            this.saveDatabase();
        }
    }

    logAction(address, action, details = null) {
        this.data.scanLog.push({
            id: this.data.scanLog.length + 1,
            contractAddress: address,
            action,
            details,
            createdAt: new Date().toISOString()
        });
        // Keep log size reasonable
        if (this.data.scanLog.length > 1000) {
            this.data.scanLog = this.data.scanLog.slice(-1000);
        }
        this.saveDatabase();
    }

    getStats() {
        const contracts = Object.values(this.data.contracts);
        return {
            monitoredCount: contracts.length,
            lastScanTime: this.data.lastScan || null,
        };
    }

    getRecentContracts(limit = 20) {
        return Object.values(this.data.contracts)
            .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
            .slice(0, limit);
    }

    // ─── Utilities ───

    hashCode(code) {
        // Simple hash for deduplication
        let hash = 0;
        for (let i = 0; i < Math.min(code.length, 1000); i++) {
            const chr = code.charCodeAt(i);
            hash = (hash << 5) - hash + chr;
            hash |= 0;
        }
        return hash.toString(16);
    }

    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    /**
     * Stop monitoring
     */
    async stopMonitoring() {
        this.isMonitoring = false;
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
        console.log("🛑 Contract monitoring stopped");
    }
}
