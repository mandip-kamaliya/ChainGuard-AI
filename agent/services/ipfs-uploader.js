const axios = require('axios');

class IPFSUploader {
    constructor() {
        this.apiKey = process.env.PINATA_API_KEY || '';
        this.secretKey = process.env.PINATA_SECRET_API_KEY || '';
        this.gateway = 'https://gateway.pinata.cloud/ipfs/';
        this.pinataUrl = 'https://api.pinata.cloud';
    }

    /**
     * Upload audit report JSON to IPFS via Pinata
     * @param {Object} report - Audit report data
     * @param {string} contractAddress - Contract address for metadata
     * @returns {Object} { ipfsHash, url }
     */
    async uploadReport(report, contractAddress) {
        try {
            const payload = {
                pinataContent: {
                    version: '1.0',
                    timestamp: new Date().toISOString(),
                    contractAddress,
                    ...report
                },
                pinataMetadata: {
                    name: `ChainGuard-Audit-${contractAddress.slice(0, 10)}-${Date.now()}`,
                    keyvalues: {
                        contractAddress,
                        riskLevel: report.riskLevel || 'UNKNOWN',
                        scanner: 'ChainGuard AI',
                        timestamp: new Date().toISOString()
                    }
                },
                pinataOptions: {
                    cidVersion: 1
                }
            };

            const { data } = await axios.post(
                `${this.pinataUrl}/pinning/pinJSONToIPFS`,
                payload,
                {
                    headers: {
                        'Content-Type': 'application/json',
                        pinata_api_key: this.apiKey,
                        pinata_secret_api_key: this.secretKey
                    },
                    timeout: 30000
                }
            );

            const ipfsHash = data.IpfsHash;
            console.log(`📌 Report pinned to IPFS: ${ipfsHash}`);

            return {
                ipfsHash,
                url: `${this.gateway}${ipfsHash}`,
                size: data.PinSize,
                timestamp: data.Timestamp
            };
        } catch (error) {
            console.error('IPFS upload error:', error.message);

            // Return a placeholder hash for offline/demo mode
            const fallbackHash = `Qm${Buffer.from(contractAddress + Date.now()).toString('base64').slice(0, 44)}`;
            console.log(`⚠️ Using fallback hash: ${fallbackHash}`);

            return {
                ipfsHash: fallbackHash,
                url: `${this.gateway}${fallbackHash}`,
                size: 0,
                timestamp: new Date().toISOString(),
                offline: true
            };
        }
    }

    /**
     * Retrieve report from IPFS
     * @param {string} ipfsHash - IPFS CID
     * @returns {Object} Report data
     */
    async getReport(ipfsHash) {
        try {
            const { data } = await axios.get(`${this.gateway}${ipfsHash}`, {
                timeout: 15000
            });
            return data;
        } catch (error) {
            console.error(`Error fetching IPFS hash ${ipfsHash}:`, error.message);
            return null;
        }
    }

    /**
     * Check if Pinata connection is healthy
     * @returns {boolean}
     */
    async isConnected() {
        try {
            await axios.get(`${this.pinataUrl}/data/testAuthentication`, {
                headers: {
                    pinata_api_key: this.apiKey,
                    pinata_secret_api_key: this.secretKey
                },
                timeout: 5000
            });
            return true;
        } catch {
            return false;
        }
    }
}

module.exports = IPFSUploader;
