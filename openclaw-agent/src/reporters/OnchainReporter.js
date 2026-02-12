/**
 * OnchainReporter — Submit vulnerability reports to SecurityRegistry
 *
 * Connects to the deployed SecurityRegistry contract on BSC/opBNB,
 * submits vulnerability findings with proper gas estimation and
 * transaction retry logic.
 */

import { Web3 } from "web3";

const SECURITY_REGISTRY_ABI = [
    {
        inputs: [
            { name: "_contractAddress", type: "address" },
            { name: "_ipfsHash", type: "string" },
            { name: "_critical", type: "uint8" },
            { name: "_high", type: "uint8" },
            { name: "_medium", type: "uint8" },
            { name: "_low", type: "uint8" },
        ],
        name: "reportVulnerability",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ name: "_contractAddress", type: "address" }],
        name: "registerContract",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ name: "_contractAddress", type: "address" }],
        name: "isMonitored",
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "reportCounter",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ name: "_contractAddress", type: "address" }],
        name: "pauseContract",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        anonymous: false,
        inputs: [
            { indexed: true, name: "reportId", type: "uint256" },
            { indexed: true, name: "contractAddress", type: "address" },
            { indexed: false, name: "severity", type: "uint8" },
        ],
        name: "VulnerabilityReported",
        type: "event",
    },
];

export class OnchainReporter {
    constructor(web3) {
        this.web3 = web3;
        this.contract = null;
        this.account = null;
        this.maxRetries = 3;
        this.retryDelay = 5000; // 5 seconds between retries
        this.initialized = false;

        this.init();
    }

    /**
     * Initialize wallet and contract connection
     */
    init() {
        const privateKey = process.env.PRIVATE_KEY;
        const registryAddress = process.env.SECURITY_REGISTRY_ADDRESS;

        if (!privateKey || privateKey.includes("your_")) {
            console.warn(
                "⚠️  PRIVATE_KEY not set — on-chain reporting disabled"
            );
            return;
        }

        if (!registryAddress) {
            console.warn(
                "⚠️  SECURITY_REGISTRY_ADDRESS not set — on-chain reporting disabled"
            );
            return;
        }

        try {
            // Add account from private key
            const key = privateKey.startsWith("0x")
                ? privateKey
                : `0x${privateKey}`;
            this.account = this.web3.eth.accounts.privateKeyToAccount(key);
            this.web3.eth.accounts.wallet.add(this.account);
            this.web3.eth.defaultAccount = this.account.address;

            // Connect to SecurityRegistry
            this.contract = new this.web3.eth.Contract(
                SECURITY_REGISTRY_ABI,
                registryAddress
            );

            this.initialized = true;
            console.log(
                `⛓️  On-chain reporter ready — wallet: ${this.account.address}`
            );
            console.log(
                `   SecurityRegistry: ${registryAddress}`
            );
        } catch (err) {
            console.error("On-chain reporter init error:", err.message);
        }
    }

    /**
     * Submit a vulnerability report on-chain
     * @param {string} contractAddress - Vulnerable contract address
     * @param {string} ipfsHash - IPFS CID of full report
     * @param {Object} counts - { critical, high, medium, low }
     * @returns {string} Transaction hash
     */
    async submitReport(contractAddress, ipfsHash, counts) {
        if (!this.initialized) {
            throw new Error("On-chain reporter not initialized");
        }

        // Ensure contract is registered first
        await this.ensureRegistered(contractAddress);

        // Cap severity counts to uint8 range
        const critical = Math.min(counts.critical || 0, 255);
        const high = Math.min(counts.high || 0, 255);
        const medium = Math.min(counts.medium || 0, 255);
        const low = Math.min(counts.low || 0, 255);

        // Build transaction with retries
        for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
            try {
                // Estimate gas
                const gasEstimate = await this.contract.methods
                    .reportVulnerability(
                        contractAddress,
                        ipfsHash,
                        critical,
                        high,
                        medium,
                        low
                    )
                    .estimateGas({ from: this.account.address });

                // Get current gas price
                const gasPrice = await this.web3.eth.getGasPrice();

                // Send transaction
                const receipt = await this.contract.methods
                    .reportVulnerability(
                        contractAddress,
                        ipfsHash,
                        critical,
                        high,
                        medium,
                        low
                    )
                    .send({
                        from: this.account.address,
                        gas: Math.ceil(Number(gasEstimate) * 1.3), // 30% buffer
                        gasPrice: gasPrice.toString(),
                    });

                return receipt.transactionHash;
            } catch (err) {
                console.error(
                    `   Attempt ${attempt}/${this.maxRetries} failed:`,
                    err.message.slice(0, 80)
                );

                if (attempt === this.maxRetries) {
                    throw new Error(
                        `Report submission failed after ${this.maxRetries} attempts: ${err.message}`
                    );
                }

                // Exponential backoff
                const delay = this.retryDelay * Math.pow(2, attempt - 1);
                console.log(`   Retrying in ${delay / 1000}s...`);
                await this.sleep(delay);
            }
        }
    }

    /**
     * Ensure a contract is registered in SecurityRegistry before reporting
     */
    async ensureRegistered(contractAddress) {
        try {
            const isMonitored = await this.contract.methods
                .isMonitored(contractAddress)
                .call();

            if (!isMonitored) {
                console.log(`   Registering ${contractAddress.slice(0, 10)}... on SecurityRegistry`);

                const gasEstimate = await this.contract.methods
                    .registerContract(contractAddress)
                    .estimateGas({ from: this.account.address });

                const gasPrice = await this.web3.eth.getGasPrice();

                await this.contract.methods
                    .registerContract(contractAddress)
                    .send({
                        from: this.account.address,
                        gas: Math.ceil(Number(gasEstimate) * 1.3),
                        gasPrice: gasPrice.toString(),
                    });

                console.log(`   ✅ Contract registered`);
            }
        } catch (err) {
            // Registration might fail if already registered or not owner — that's OK
            console.warn(
                `   Registration skipped: ${err.message.slice(0, 60)}`
            );
        }
    }

    /**
     * Pause a contract via SecurityRegistry (for critical vulnerabilities)
     * @param {string} contractAddress - Contract to pause
     * @returns {string} Transaction hash
     */
    async pauseContract(contractAddress) {
        if (!this.initialized) {
            throw new Error("On-chain reporter not initialized");
        }

        try {
            const gasEstimate = await this.contract.methods
                .pauseContract(contractAddress)
                .estimateGas({ from: this.account.address });

            const gasPrice = await this.web3.eth.getGasPrice();

            const receipt = await this.contract.methods
                .pauseContract(contractAddress)
                .send({
                    from: this.account.address,
                    gas: Math.ceil(Number(gasEstimate) * 1.3),
                    gasPrice: gasPrice.toString(),
                });

            return receipt.transactionHash;
        } catch (err) {
            console.error("Pause contract error:", err.message);
            throw err;
        }
    }

    /**
     * Get current report counter from SecurityRegistry
     * @returns {number} Total reports filed
     */
    async getReportCount() {
        if (!this.initialized) return 0;

        try {
            const count = await this.contract.methods.reportCounter().call();
            return Number(count);
        } catch {
            return 0;
        }
    }

    /**
     * Check wallet balance
     * @returns {string} Balance in BNB
     */
    async getBalance() {
        if (!this.account) return "0";

        try {
            const balance = await this.web3.eth.getBalance(
                this.account.address
            );
            return this.web3.utils.fromWei(balance, "ether");
        } catch {
            return "0";
        }
    }

    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}
