const { ethers } = require('ethers');
const OpenAI = require('openai');
require('dotenv').config();

class ChainGuardAIAgent {
    constructor() {
        this.provider = new ethers.JsonRpcProvider(process.env.RPC_URL_BSC_TESTNET);
        this.wallet = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);
        this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
        this.contractAddress = null;
        this.contract = null;
    }

    async initialize(contractAddress) {
        this.contractAddress = contractAddress;
        
        // Contract ABI (simplified version)
        const abi = [
            "function fileSecurityReport(address _contractAddress, string _riskLevel, string _vulnerabilityType, string _description) external",
            "function getMonitoredContract(address _contractAddress) external view returns (tuple(address contractAddress, bool isActive, uint256 monitoringStart, uint256 lastCheck, uint256 alertCount))",
            "event SecurityReportFiled(uint256 indexed reportId, address indexed contractAddress, string riskLevel, string vulnerabilityType)"
        ];
        
        this.contract = new ethers.Contract(contractAddress, abi, this.wallet);
        console.log(`ChainGuard AI Agent initialized with contract at ${contractAddress}`);
    }

    async analyzeContract(contractCode, contractAddress) {
        try {
            const analysis = await this.openai.chat.completions.create({
                model: "gpt-4",
                messages: [
                    {
                        role: "system",
                        content: `You are a smart contract security expert. Analyze the provided contract code for vulnerabilities.
                        Return a JSON response with:
                        {
                            "riskLevel": "LOW" | "MEDIUM" | "HIGH" | "CRITICAL",
                            "vulnerabilityType": "string",
                            "description": "detailed description of the vulnerability",
                            "recommendations": "how to fix the issue"
                        }`
                    },
                    {
                        role: "user",
                        content: `Analyze this contract for security vulnerabilities:\n\n${contractCode}`
                    }
                ],
                temperature: 0.1
            });

            return JSON.parse(analysis.choices[0].message.content);
        } catch (error) {
            console.error("Error analyzing contract:", error);
            return {
                riskLevel: "MEDIUM",
                vulnerabilityType: "ANALYSIS_ERROR",
                description: "Failed to analyze contract automatically",
                recommendations: "Manual security review required"
            };
        }
    }

    async getContractSource(contractAddress) {
        try {
            // Try to get source code from BscScan API
            const response = await fetch(`https://api-testnet.bscscan.com/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${process.env.BSCSCAN_API_KEY}`);
            const data = await response.json();
            
            if (data.result && data.result[0] && data.result[0].SourceCode) {
                return data.result[0].SourceCode;
            }
            
            // Fallback: try to get bytecode and decompile (limited)
            const bytecode = await this.provider.getCode(contractAddress);
            if (bytecode === '0x') {
                throw new Error('No contract code found at address');
            }
            
            return `// Bytecode analysis\n// Contract at ${contractAddress}\n// Bytecode: ${bytecode.slice(0, 200)}...`;
        } catch (error) {
            console.error("Error getting contract source:", error);
            return null;
        }
    }

    async monitorContract(contractAddress) {
        try {
            console.log(`Starting monitoring for contract: ${contractAddress}`);
            
            // Get contract source code
            const sourceCode = await this.getContractSource(contractAddress);
            if (!sourceCode) {
                console.log("Could not retrieve source code, skipping analysis");
                return;
            }
            
            // Analyze with AI
            const analysis = await this.analyzeContract(sourceCode, contractAddress);
            console.log("AI Analysis result:", analysis);
            
            // File security report onchain
            const tx = await this.contract.fileSecurityReport(
                contractAddress,
                analysis.riskLevel,
                analysis.vulnerabilityType,
                analysis.description
            );
            
            console.log(`Security report filed onchain. Transaction: ${tx.hash}`);
            await tx.wait();
            
            // If critical vulnerability found, take additional actions
            if (analysis.riskLevel === "CRITICAL") {
                await this.handleCriticalVulnerability(contractAddress, analysis);
            }
            
            return {
                contractAddress,
                analysis,
                transactionHash: tx.hash
            };
            
        } catch (error) {
            console.error("Error monitoring contract:", error);
            throw error;
        }
    }

    async handleCriticalVulnerability(contractAddress, analysis) {
        console.log(`CRITICAL vulnerability detected in ${contractAddress}`);
        
        // In a real implementation, this could:
        // 1. Send alerts to contract owner
        // 2. Attempt to pause the contract if possible
        // 3. Notify the community
        // 4. Create emergency proposals for DAOs
        
        // For demo purposes, we'll just log the critical finding
        const alert = {
            timestamp: new Date().toISOString(),
            contract: contractAddress,
            riskLevel: "CRITICAL",
            vulnerability: analysis.vulnerabilityType,
            description: analysis.description,
            action: "Contract flagged for immediate security review"
        };
        
        console.log("CRITICAL ALERT:", JSON.stringify(alert, null, 2));
        
        // Store alert for web interface
        this.storeAlert(alert);
    }

    storeAlert(alert) {
        // In a real implementation, this would store to a database
        // For now, we'll just keep it in memory
        if (!this.alerts) {
            this.alerts = [];
        }
        this.alerts.push(alert);
        
        // Keep only last 100 alerts
        if (this.alerts.length > 100) {
            this.alerts = this.alerts.slice(-100);
        }
    }

    getAlerts() {
        return this.alerts || [];
    }

    async continuousMonitoring() {
        console.log("Starting continuous monitoring mode...");
        
        // Monitor every 5 minutes
        setInterval(async () => {
            try {
                // Get list of monitored contracts from the ChainGuard contract
                // This would require additional contract functions
                console.log("Running periodic security check...");
                
                // For demo, monitor a sample contract
                const sampleContract = "0x742d35Cc6634C0532925a3b8D4C9db96C4b4Db45"; // Example BSC testnet contract
                await this.monitorContract(sampleContract);
                
            } catch (error) {
                console.error("Error in continuous monitoring:", error);
            }
        }, 5 * 60 * 1000); // 5 minutes
    }
}

module.exports = ChainGuardAIAgent;
