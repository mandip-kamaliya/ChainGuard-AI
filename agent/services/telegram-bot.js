const axios = require('axios');

class TelegramBot {
    constructor() {
        this.token = process.env.TELEGRAM_BOT_TOKEN || '';
        this.chatId = process.env.TELEGRAM_CHAT_ID || '';
        this.baseUrl = `https://api.telegram.org/bot${this.token}`;
        this.enabled = !!(this.token && this.chatId);
    }

    /**
     * Send a vulnerability alert to Telegram
     * @param {Object} alert - Alert data
     */
    async sendAlert(alert) {
        if (!this.enabled) {
            console.log('📱 Telegram not configured, skipping alert');
            return;
        }

        const severityEmoji = {
            CRITICAL: '🔴',
            HIGH: '🟠',
            MEDIUM: '🟡',
            LOW: '🟢',
            SAFE: '✅'
        };

        const emoji = severityEmoji[alert.riskLevel] || '⚪';

        const message = `
${emoji} *ChainGuard AI Alert* ${emoji}

*Risk Level:* ${alert.riskLevel}
*Contract:* \`${alert.contractAddress}\`
*Score:* ${alert.overallScore || 'N/A'}/100

*Summary:* ${alert.summary || 'No summary'}

${alert.vulnerabilities?.length > 0 ? `*Top Findings:*
${alert.vulnerabilities.slice(0, 3).map((v, i) =>
            `${i + 1}. [${v.severity}] ${v.title}`
        ).join('\n')}` : '*No vulnerabilities found* ✅'}

${alert.ipfsHash ? `📋 [Full Report](https://gateway.pinata.cloud/ipfs/${alert.ipfsHash})` : ''}
⏰ ${new Date().toISOString()}
    `.trim();

        try {
            await axios.post(`${this.baseUrl}/sendMessage`, {
                chat_id: this.chatId,
                text: message,
                parse_mode: 'Markdown',
                disable_web_page_preview: true
            });
            console.log(`📱 Telegram alert sent for ${alert.contractAddress}`);
        } catch (error) {
            console.error('Telegram send error:', error.message);
        }
    }

    /**
     * Send a simple status message
     * @param {string} text - Message text
     */
    async sendMessage(text) {
        if (!this.enabled) return;

        try {
            await axios.post(`${this.baseUrl}/sendMessage`, {
                chat_id: this.chatId,
                text: `🛡️ *ChainGuard AI*\n\n${text}`,
                parse_mode: 'Markdown'
            });
        } catch (error) {
            console.error('Telegram message error:', error.message);
        }
    }

    /**
     * Send daily summary
     * @param {Object} stats - { totalScans, criticalFindings, contractsMonitored }
     */
    async sendDailySummary(stats) {
        const message = `
📊 *Daily Security Summary*

🔍 Scans completed: ${stats.totalScans || 0}
🚨 Critical findings: ${stats.criticalFindings || 0}
📋 Contracts monitored: ${stats.contractsMonitored || 0}
⏰ Report time: ${new Date().toISOString()}
    `.trim();

        await this.sendMessage(message);
    }

    /**
     * Check if bot is connected
     * @returns {boolean}
     */
    async isConnected() {
        if (!this.enabled) return false;
        try {
            const { data } = await axios.get(`${this.baseUrl}/getMe`, { timeout: 5000 });
            return data.ok === true;
        } catch {
            return false;
        }
    }
}

module.exports = TelegramBot;
