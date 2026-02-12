const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');
const { ethers } = require('ethers');
require('dotenv').config();

// Import services
const ClaudeAnalyzer = require('./services/claude-analyzer');
const ContractMonitor = require('./services/contract-monitor');
const IPFSUploader = require('./services/ipfs-uploader');
const OnchainReporter = require('./services/onchain-reporter');
const TelegramBot = require('./services/telegram-bot');
const ScanDatabase = require('./services/database');

// ────────────────────────────────────────────
// Initialize services
// ────────────────────────────────────────────

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] }
});

// Blockchain provider + wallet
const rpcUrl = process.env.RPC_URL || process.env.RPC_URL_BSC_TESTNET || 'https://data-seed-prebsc-1-s1.binance.org:8545/';
const provider = new ethers.JsonRpcProvider(rpcUrl);
const wallet = process.env.PRIVATE_KEY
    ? new ethers.Wallet(process.env.PRIVATE_KEY, provider)
    : null;

// Services
const claude = new ClaudeAnalyzer();
const monitor = new ContractMonitor(provider);
const ipfs = new IPFSUploader();
const telegram = new TelegramBot();
const db = new ScanDatabase();
const onchain = wallet ? new OnchainReporter(wallet) : null;

// Connect to deployed contracts if address provided
if (onchain && process.env.CHAIN_GUARD_CONTRACT_ADDRESS) {
    onchain.connect(
        process.env.CHAIN_GUARD_CONTRACT_ADDRESS,
        process.env.SECURITY_REGISTRY_ADDRESS || null,
        process.env.AUDIT_NFT_ADDRESS || null
    );
}

// ────────────────────────────────────────────
// Middleware
// ────────────────────────────────────────────

app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'frontend', 'dist')));
app.use(express.static(path.join(__dirname, '..', 'public')));

// ────────────────────────────────────────────
// Core scan pipeline
// ────────────────────────────────────────────

async function runScan(contractAddress) {
    console.log(`\n🔍 ── Scanning ${contractAddress} ──`);
    const startTime = Date.now();

    // 1. Fetch source code
    const sourceInfo = await monitor.getSourceCode(contractAddress);
    if (!sourceInfo) {
        throw new Error(`No code found at ${contractAddress}`);
    }

    // 2. AI analysis with Claude
    console.log('🤖 Running Claude analysis...');
    const analysis = await claude.analyzeContract(sourceInfo.source, contractAddress);

    // 3. Upload report to IPFS
    console.log('📌 Uploading to IPFS...');
    const ipfsResult = await ipfs.uploadReport(analysis, contractAddress);

    // 4. Count vulnerabilities
    const counts = {
        critical: analysis.vulnerabilities?.filter(v => v.severity === 'CRITICAL').length || 0,
        high: analysis.vulnerabilities?.filter(v => v.severity === 'HIGH').length || 0,
        medium: analysis.vulnerabilities?.filter(v => v.severity === 'MEDIUM').length || 0,
        low: analysis.vulnerabilities?.filter(v => v.severity === 'LOW').length || 0,
    };

    // 5. Submit on-chain (if connected)
    let onchainResult = null;
    if (onchain) {
        try {
            onchainResult = await onchain.submitReport(contractAddress, ipfsResult.ipfsHash, counts);
        } catch (err) {
            console.warn('⚠️ On-chain report skipped:', err.message);
        }
    }

    // 6. Save to database
    const scanId = db.saveScan({
        contractAddress,
        contractName: sourceInfo.name,
        riskLevel: analysis.riskLevel,
        overallScore: analysis.overallScore,
        ...counts,
        ipfsHash: ipfsResult.ipfsHash,
        reportId: onchainResult?.reportId || null,
        certificateId: onchainResult?.certificateId || null,
        txHash: onchainResult?.txHash || null,
        sourceVerified: sourceInfo.verified,
        analysisJson: analysis
    });

    db.updateLastScan(contractAddress);

    // 7. Send alerts for CRITICAL/HIGH
    if (analysis.riskLevel === 'CRITICAL' || analysis.riskLevel === 'HIGH') {
        await telegram.sendAlert({
            ...analysis,
            contractAddress,
            ipfsHash: ipfsResult.ipfsHash
        });

        // Save alert to DB
        for (const vuln of (analysis.vulnerabilities || []).filter(v => v.severity === 'CRITICAL' || v.severity === 'HIGH')) {
            db.saveAlert({
                contractAddress,
                severity: vuln.severity,
                title: vuln.title,
                description: vuln.description
            });
        }
    }

    const result = {
        id: scanId,
        contractAddress,
        contractName: sourceInfo.name,
        riskLevel: analysis.riskLevel,
        overallScore: analysis.overallScore,
        vulnerabilities: analysis.vulnerabilities || [],
        counts,
        ipfsHash: ipfsResult.ipfsHash,
        ipfsUrl: ipfsResult.url,
        onchain: onchainResult,
        verified: sourceInfo.verified,
        duration: Date.now() - startTime,
        timestamp: new Date().toISOString()
    };

    // 8. Emit to connected WebSocket clients
    io.emit('scanResult', result);

    console.log(`✅ Scan complete in ${result.duration}ms — ${analysis.riskLevel} (${analysis.overallScore}/100)`);
    return result;
}

// ────────────────────────────────────────────
// API Routes
// ────────────────────────────────────────────

// Health / Status
app.get('/api/status', async (req, res) => {
    const stats = db.getStats();
    const chainConnected = !!onchain;
    const ipfsConnected = await ipfs.isConnected().catch(() => false);
    const telegramConnected = await telegram.isConnected().catch(() => false);

    res.json({
        status: 'active',
        version: '2.0.0',
        services: {
            claude: !!process.env.ANTHROPIC_API_KEY,
            blockchain: chainConnected,
            ipfs: ipfsConnected,
            telegram: telegramConnected,
            database: true
        },
        stats,
        monitoring: monitor.isMonitoring,
        wallet: wallet ? wallet.address : null,
        timestamp: new Date().toISOString()
    });
});

// Manual scan
app.post('/api/scan', async (req, res) => {
    try {
        const { contractAddress } = req.body;
        if (!contractAddress || !ethers.isAddress(contractAddress)) {
            return res.status(400).json({ error: 'Valid contract address required' });
        }

        const result = await runScan(contractAddress);
        res.json(result);
    } catch (error) {
        console.error('Scan error:', error.message);
        res.status(500).json({ error: error.message });
    }
});

// Get recent scans
app.get('/api/scans', (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const scans = db.getRecentScans(limit);
    res.json({ scans, total: scans.length });
});

// Get scan by ID
app.get('/api/scans/:id', (req, res) => {
    const scan = db.getScanById(parseInt(req.params.id));
    if (!scan) return res.status(404).json({ error: 'Scan not found' });

    // Parse analysis JSON
    if (scan.analysis_json) {
        try { scan.analysis = JSON.parse(scan.analysis_json); } catch { }
    }
    res.json(scan);
});

// Get scans for a contract
app.get('/api/contracts/:address/scans', (req, res) => {
    const scans = db.getScansByContract(req.params.address);
    res.json({ scans, total: scans.length });
});

// Get alerts
app.get('/api/alerts', (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const alerts = db.getRecentAlerts(limit);
    res.json({ alerts, total: alerts.length });
});

// Get system stats
app.get('/api/stats', (req, res) => {
    res.json(db.getStats());
});

// Get IPFS report
app.get('/api/ipfs/:hash', async (req, res) => {
    try {
        const report = await ipfs.getReport(req.params.hash);
        if (!report) return res.status(404).json({ error: 'Report not found' });
        res.json(report);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Start/stop continuous monitoring
app.post('/api/monitor/start', async (req, res) => {
    try {
        await monitor.startMonitoring(async (contractAddress, meta) => {
            console.log(`🆕 Auto-scanning new contract: ${contractAddress}`);
            db.addMonitoredContract({
                address: contractAddress,
                deployer: meta.deployer,
                name: 'Auto-detected'
            });

            try {
                await runScan(contractAddress);
            } catch (err) {
                console.error(`Auto-scan failed for ${contractAddress}:`, err.message);
            }
        });

        io.emit('monitoringStatus', { active: true });
        res.json({ message: 'Monitoring started', active: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/monitor/stop', (req, res) => {
    monitor.stopMonitoring();
    io.emit('monitoringStatus', { active: false });
    res.json({ message: 'Monitoring stopped', active: false });
});

// Get monitored contracts
app.get('/api/contracts', (req, res) => {
    res.json({ contracts: db.getMonitoredContracts() });
});

// Add contract to monitoring
app.post('/api/contracts', (req, res) => {
    const { address, name, scanInterval } = req.body;
    if (!address || !ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Valid contract address required' });
    }
    db.addMonitoredContract({ address, name, scanInterval });
    res.json({ message: 'Contract added', address });
});

// Serve frontend SPA for all other routes
app.get('*', (req, res) => {
    const indexPath = path.join(__dirname, '..', 'frontend', 'dist', 'index.html');
    const publicPath = path.join(__dirname, '..', 'public', 'index.html');
    const fs = require('fs');

    if (fs.existsSync(indexPath)) {
        res.sendFile(indexPath);
    } else if (fs.existsSync(publicPath)) {
        res.sendFile(publicPath);
    } else {
        res.json({ message: 'ChainGuard AI Agent API v2.0.0', docs: '/api/status' });
    }
});

// ────────────────────────────────────────────
// WebSocket
// ────────────────────────────────────────────

io.on('connection', (socket) => {
    console.log(`🔌 Client connected: ${socket.id}`);

    // Send current state
    socket.emit('stats', db.getStats());
    socket.emit('recentScans', db.getRecentScans(10));
    socket.emit('monitoringStatus', { active: monitor.isMonitoring });

    socket.on('requestScan', async (data) => {
        try {
            const result = await runScan(data.contractAddress);
            socket.emit('scanComplete', result);
        } catch (error) {
            socket.emit('scanError', { error: error.message });
        }
    });

    socket.on('disconnect', () => {
        console.log(`🔌 Client disconnected: ${socket.id}`);
    });
});

// ────────────────────────────────────────────
// Start server
// ────────────────────────────────────────────

const PORT = process.env.PORT || 3001;

server.listen(PORT, () => {
    console.log('');
    console.log('╔════════════════════════════════════════════╗');
    console.log('║     🛡️  ChainGuard AI Agent v2.0.0         ║');
    console.log('╠════════════════════════════════════════════╣');
    console.log(`║  🌐 API:       http://localhost:${PORT}       ║`);
    console.log(`║  📊 Dashboard: http://localhost:${PORT}       ║`);
    console.log(`║  🤖 AI:        Claude Sonnet 4             ║`);
    console.log(`║  ⛓️  Chain:     ${rpcUrl.includes('opbnb') ? 'opBNB Testnet' : 'BSC Testnet'}        ║`);
    console.log('╚════════════════════════════════════════════╝');
    console.log('');

    if (!process.env.ANTHROPIC_API_KEY) console.warn('⚠️  ANTHROPIC_API_KEY not set');
    if (!process.env.PRIVATE_KEY || process.env.PRIVATE_KEY.includes('1234')) console.warn('⚠️  PRIVATE_KEY not set (using placeholder)');
    if (!process.env.PINATA_API_KEY) console.warn('⚠️  PINATA_API_KEY not set — IPFS will use fallback');
    if (!process.env.TELEGRAM_BOT_TOKEN) console.warn('⚠️  TELEGRAM_BOT_TOKEN not set — alerts disabled');
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down...');
    monitor.stopMonitoring();
    db.close();
    server.close();
    process.exit(0);
});

process.on('unhandledRejection', (reason) => {
    console.error('Unhandled rejection:', reason);
});
