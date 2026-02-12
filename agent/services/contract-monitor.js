const { ethers } = require('ethers');
const axios = require('axios');

class ContractMonitor {
    constructor(provider) {
        this.provider = provider;
        this.bscscanApiKey = process.env.BSCSCAN_API_KEY || '';
        this.isMonitoring = false;
        this.onNewContract = null; // callback
    }

    /**
     * Fetch verified source code from BSCScan API
     * @param {string} address - Contract address
     * @returns {string|null} Source code or null
     */
    async getSourceCode(address) {
        try {
            // Try BSC testnet API first
            const endpoints = [
                `https://api-testnet.bscscan.com/api`,
                `https://api.bscscan.com/api`,
                `https://api-opbnb-testnet.bscscan.com/api`
            ];

            for (const baseUrl of endpoints) {
                try {
                    const { data } = await axios.get(baseUrl, {
                        params: {
                            module: 'contract',
                            action: 'getsourcecode',
                            address,
                            apikey: this.bscscanApiKey
                        },
                        timeout: 10000
                    });

                    if (data.result?.[0]?.SourceCode && data.result[0].SourceCode !== '') {
                        console.log(`✅ Source code found for ${address} via ${baseUrl}`);
                        return {
                            source: data.result[0].SourceCode,
                            name: data.result[0].ContractName || 'Unknown',
                            compiler: data.result[0].CompilerVersion || 'Unknown',
                            verified: true
                        };
                    }
                } catch {
                    continue;
                }
            }

            // Fallback: get bytecode for bytecode-level analysis
            const bytecode = await this.provider.getCode(address);
            if (bytecode && bytecode !== '0x') {
                console.log(`⚙️ Using bytecode for ${address} (not verified)`);
                return {
                    source: `// Unverified contract bytecode\n// Address: ${address}\n// Bytecode length: ${bytecode.length} chars\n// Bytecode: ${bytecode.slice(0, 500)}...`,
                    name: 'Unverified Contract',
                    compiler: 'N/A',
                    verified: false,
                    bytecode
                };
            }

            console.log(`❌ No code found at ${address}`);
            return null;
        } catch (error) {
            console.error(`Error fetching source for ${address}:`, error.message);
            return null;
        }
    }

    /**
     * Start monitoring for new contract deployments
     * Uses polling of recent blocks to detect null-to contracts
     * @param {function} callback - Called with new contract address
     */
    async startMonitoring(callback) {
        if (this.isMonitoring) {
            console.log('⚠️ Already monitoring');
            return;
        }

        this.isMonitoring = true;
        this.onNewContract = callback;
        console.log('🔍 Contract deployment monitoring started');

        let lastBlock = await this.provider.getBlockNumber();

        this.monitorInterval = setInterval(async () => {
            try {
                const currentBlock = await this.provider.getBlockNumber();

                for (let blockNum = lastBlock + 1; blockNum <= currentBlock; blockNum++) {
                    const block = await this.provider.getBlock(blockNum, true);
                    if (!block || !block.transactions) continue;

                    for (const txHash of block.transactions) {
                        try {
                            const receipt = await this.provider.getTransactionReceipt(txHash);
                            if (receipt?.contractAddress) {
                                console.log(`🆕 New contract deployed: ${receipt.contractAddress} (block ${blockNum})`);
                                if (this.onNewContract) {
                                    this.onNewContract(receipt.contractAddress, {
                                        deployer: receipt.from,
                                        txHash: receipt.hash,
                                        blockNumber: blockNum,
                                        timestamp: block.timestamp
                                    });
                                }
                            }
                        } catch {
                            // Skip failed receipt fetches
                        }
                    }
                }

                lastBlock = currentBlock;
            } catch (error) {
                console.error('Monitor polling error:', error.message);
            }
        }, 15000); // Poll every 15 seconds
    }

    /**
     * Stop monitoring
     */
    stopMonitoring() {
        this.isMonitoring = false;
        if (this.monitorInterval) {
            clearInterval(this.monitorInterval);
            this.monitorInterval = null;
        }
        console.log('🛑 Contract monitoring stopped');
    }

    /**
     * Get contract creation info
     * @param {string} address - Contract address
     * @returns {Object} Creation info
     */
    async getContractInfo(address) {
        try {
            const code = await this.provider.getCode(address);
            const balance = await this.provider.getBalance(address);

            return {
                address,
                hasCode: code !== '0x',
                codeSize: code ? (code.length - 2) / 2 : 0, // bytes
                balance: ethers.formatEther(balance),
                isContract: code !== '0x'
            };
        } catch (error) {
            console.error(`Error getting contract info for ${address}:`, error.message);
            return null;
        }
    }
}

module.exports = ContractMonitor;
