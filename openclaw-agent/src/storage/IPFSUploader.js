/**
 * IPFSUploader — Upload audit reports to IPFS via Pinata
 *
 * Pins JSON reports to IPFS using the Pinata API and returns CIDs.
 * Includes fallback for offline/demo mode.
 */

import axios from "axios";

export class IPFSUploader {
    constructor() {
        this.apiKey = process.env.PINATA_API_KEY || "";
        this.secretKey = process.env.PINATA_SECRET_API_KEY || "";
        this.gateway =
            process.env.IPFS_GATEWAY || "https://gateway.pinata.cloud/ipfs/";
        this.pinataUrl = "https://api.pinata.cloud";
        this.enabled = !!(this.apiKey && this.secretKey);

        if (this.enabled) {
            console.log("📌 IPFS uploader ready (Pinata)");
        } else {
            console.warn("⚠️  Pinata keys not set — IPFS will use fallback hashes");
        }
    }

    /**
     * Upload a JSON report to IPFS via Pinata
     * @param {Object} reportData - Report data to upload
     * @returns {string} IPFS CID (hash)
     */
    async upload(reportData) {
        if (!this.enabled) {
            return this.generateFallbackHash(reportData);
        }

        try {
            const payload = {
                pinataContent: {
                    version: "1.0",
                    scanner: "ChainGuard AI",
                    timestamp: new Date().toISOString(),
                    ...reportData,
                },
                pinataMetadata: {
                    name: `ChainGuard-Report-${reportData.contract?.slice(0, 10) || "unknown"}-${Date.now()}`,
                    keyvalues: {
                        contractAddress: reportData.contract || "",
                        network: reportData.network || "BSC",
                        scanner: "ChainGuard AI",
                        vulnerabilityCount: String(
                            reportData.vulnerabilities?.length || 0
                        ),
                        timestamp: new Date().toISOString(),
                    },
                },
                pinataOptions: {
                    cidVersion: 1,
                },
            };

            const { data } = await axios.post(
                `${this.pinataUrl}/pinning/pinJSONToIPFS`,
                payload,
                {
                    headers: {
                        "Content-Type": "application/json",
                        pinata_api_key: this.apiKey,
                        pinata_secret_api_key: this.secretKey,
                    },
                    timeout: 30000,
                }
            );

            const ipfsHash = data.IpfsHash;

            console.log(`   📌 Pinned: ${ipfsHash} (${data.PinSize} bytes)`);

            return ipfsHash;
        } catch (error) {
            console.error("   IPFS upload error:", error.message);

            // Fall back to placeholder hash
            return this.generateFallbackHash(reportData);
        }
    }

    /**
     * Retrieve a report from IPFS
     * @param {string} ipfsHash - IPFS CID
     * @returns {Object|null} Report data
     */
    async retrieve(ipfsHash) {
        try {
            const { data } = await axios.get(`${this.gateway}${ipfsHash}`, {
                timeout: 15000,
            });
            return data;
        } catch (error) {
            console.error(`   IPFS retrieve error (${ipfsHash}):`, error.message);
            return null;
        }
    }

    /**
     * List pinned reports from Pinata
     * @param {number} limit - Max results
     * @returns {Array} Pinned items metadata
     */
    async listReports(limit = 20) {
        if (!this.enabled) return [];

        try {
            const { data } = await axios.get(
                `${this.pinataUrl}/data/pinList`,
                {
                    params: {
                        status: "pinned",
                        pageLimit: limit,
                        "metadata[name]": "ChainGuard-Report",
                    },
                    headers: {
                        pinata_api_key: this.apiKey,
                        pinata_secret_api_key: this.secretKey,
                    },
                    timeout: 10000,
                }
            );

            return (data.rows || []).map((row) => ({
                hash: row.ipfs_pin_hash,
                name: row.metadata?.name || "Unknown",
                size: row.size,
                date: row.date_pinned,
                metadata: row.metadata?.keyvalues || {},
            }));
        } catch (error) {
            console.error("   Pinata list error:", error.message);
            return [];
        }
    }

    /**
     * Unpin a report from Pinata
     * @param {string} ipfsHash - CID to unpin
     * @returns {boolean} Success
     */
    async unpin(ipfsHash) {
        if (!this.enabled) return false;

        try {
            await axios.delete(
                `${this.pinataUrl}/pinning/unpin/${ipfsHash}`,
                {
                    headers: {
                        pinata_api_key: this.apiKey,
                        pinata_secret_api_key: this.secretKey,
                    },
                    timeout: 10000,
                }
            );
            return true;
        } catch (error) {
            console.error(`   Unpin error (${ipfsHash}):`, error.message);
            return false;
        }
    }

    /**
     * Check Pinata authentication
     * @returns {boolean}
     */
    async isConnected() {
        if (!this.enabled) return false;

        try {
            const { data } = await axios.get(
                `${this.pinataUrl}/data/testAuthentication`,
                {
                    headers: {
                        pinata_api_key: this.apiKey,
                        pinata_secret_api_key: this.secretKey,
                    },
                    timeout: 5000,
                }
            );
            return data.message === "Congratulations! You are communicating with the Pinata API!";
        } catch {
            return false;
        }
    }

    /**
     * Get the public gateway URL for a hash
     * @param {string} ipfsHash - IPFS CID
     * @returns {string} Gateway URL
     */
    getUrl(ipfsHash) {
        return `${this.gateway}${ipfsHash}`;
    }

    /**
     * Generate a deterministic fallback hash for offline mode
     */
    generateFallbackHash(reportData) {
        const str = JSON.stringify(reportData).slice(0, 100) + Date.now();
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            const chr = str.charCodeAt(i);
            hash = (hash << 5) - hash + chr;
            hash |= 0;
        }

        const fallbackHash = `QmFALLBACK${Math.abs(hash).toString(36).padStart(34, "0")}`;
        console.warn(`   ⚠️  Using fallback IPFS hash: ${fallbackHash}`);
        return fallbackHash;
    }
}
