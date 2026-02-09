const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');
require('dotenv').config();

const ChainGuardAIAgent = require('./ai-agent');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// Initialize AI Agent
const aiAgent = new ChainGuardAIAgent();

// Store monitoring status
let monitoringStatus = {
    isActive: false,
    contracts: [],
    lastCheck: null,
    alerts: []
};

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.get('/api/status', (req, res) => {
    res.json({
        status: 'active',
        monitoring: monitoringStatus,
        alerts: aiAgent.getAlerts(),
        timestamp: new Date().toISOString()
    });
});

app.post('/api/monitor', async (req, res) => {
    try {
        const { contractAddress, contractCode } = req.body;
        
        if (!contractAddress) {
            return res.status(400).json({ error: 'Contract address required' });
        }
        
        // Initialize AI agent if not already done
        if (!aiAgent.contract) {
            // This would be the deployed ChainGuard contract address
            const contractAddress = process.env.CHAIN_GUARD_CONTRACT_ADDRESS;
            if (!contractAddress) {
                return res.status(500).json({ error: 'ChainGuard contract address not configured' });
            }
            await aiAgent.initialize(contractAddress);
        }
        
        // Start monitoring
        const result = await aiAgent.monitorContract(contractAddress);
        
        monitoringStatus.contracts.push(contractAddress);
        monitoringStatus.lastCheck = new Date().toISOString();
        
        // Emit real-time update
        io.emit('securityUpdate', {
            type: 'newReport',
            data: result
        });
        
        res.json(result);
        
    } catch (error) {
        console.error('Error in monitor endpoint:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/start-continuous', async (req, res) => {
    try {
        if (monitoringStatus.isActive) {
            return res.status(400).json({ error: 'Continuous monitoring already active' });
        }
        
        monitoringStatus.isActive = true;
        
        // Start continuous monitoring
        aiAgent.continuousMonitoring();
        
        io.emit('monitoringStatus', {
            isActive: true,
            message: 'Continuous monitoring started'
        });
        
        res.json({ message: 'Continuous monitoring started' });
        
    } catch (error) {
        console.error('Error starting continuous monitoring:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/stop-continuous', (req, res) => {
    monitoringStatus.isActive = false;
    
    io.emit('monitoringStatus', {
        isActive: false,
        message: 'Continuous monitoring stopped'
    });
    
    res.json({ message: 'Continuous monitoring stopped' });
});

app.get('/api/alerts', (req, res) => {
    res.json({
        alerts: aiAgent.getAlerts(),
        count: aiAgent.getAlerts().length
    });
});

// WebSocket connection handling
io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);
    
    // Send current status on connection
    socket.emit('monitoringStatus', monitoringStatus);
    socket.emit('alerts', aiAgent.getAlerts());
    
    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
    });
});

// Error handling
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
    process.exit(1);
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, () => {
    console.log(`🛡️  ChainGuard AI Server running on port ${PORT}`);
    console.log(`📊 Dashboard: http://localhost:${PORT}`);
    console.log(`🔍 AI Agent ready for BNB Chain security monitoring`);
});
