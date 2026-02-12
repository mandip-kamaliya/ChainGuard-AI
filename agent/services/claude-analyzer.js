const Anthropic = require('@anthropic-ai/sdk');

class ClaudeAnalyzer {
  constructor() {
    this.client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
    this.model = 'claude-sonnet-4-20250514';
  }

  /**
   * Analyze smart contract source code for vulnerabilities
   * @param {string} sourceCode - Solidity source code or bytecode
   * @param {string} contractAddress - Address of the contract
   * @returns {Object} Structured vulnerability analysis
   */
  async analyzeContract(sourceCode, contractAddress) {
    try {
      const message = await this.client.messages.create({
        model: this.model,
        max_tokens: 4096,
        system: `You are ChainGuard AI, an expert smart contract security auditor specializing in BNB Chain / EVM contracts.

Analyze the provided contract for the OWASP Smart Contract Top 10 vulnerabilities:
1. Reentrancy Attacks
2. Integer Overflow/Underflow
3. Unchecked Return Values
4. Access Control Issues
5. Front-Running / MEV
6. Denial of Service (DoS)
7. Bad Randomness
8. Time Manipulation
9. Short Address Attack
10. Known Vulnerable Dependencies

Return ONLY a valid JSON object (no markdown, no backticks) with this structure:
{
  "contractAddress": "<address>",
  "summary": "<1-2 sentence overview>",
  "riskLevel": "CRITICAL" | "HIGH" | "MEDIUM" | "LOW" | "SAFE",
  "vulnerabilities": [
    {
      "id": "<vuln-001>",
      "title": "<short title>",
      "severity": "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",
      "category": "<OWASP category>",
      "description": "<detailed description>",
      "lineNumbers": "<line range or 'N/A'>",
      "recommendation": "<fix recommendation>",
      "confidence": "HIGH" | "MEDIUM" | "LOW"
    }
  ],
  "gasOptimizations": [
    { "description": "<optimization>", "estimatedSavings": "<gas amount>" }
  ],
  "bestPractices": ["<suggestion1>", "<suggestion2>"],
  "overallScore": <0-100>
}`,
        messages: [
          {
            role: 'user',
            content: `Analyze this smart contract at address ${contractAddress} for security vulnerabilities:\n\n${sourceCode}`
          }
        ]
      });

      const responseText = message.content[0].text;
      return JSON.parse(responseText);
    } catch (error) {
      console.error('Claude analysis error:', error.message);

      // Return a fallback analysis on error
      return {
        contractAddress,
        summary: 'Automated analysis could not be completed. Manual review recommended.',
        riskLevel: 'MEDIUM',
        vulnerabilities: [
          {
            id: 'vuln-error',
            title: 'Analysis Incomplete',
            severity: 'MEDIUM',
            category: 'Analysis Error',
            description: `Automated analysis failed: ${error.message}`,
            lineNumbers: 'N/A',
            recommendation: 'Submit for manual security audit.',
            confidence: 'LOW'
          }
        ],
        gasOptimizations: [],
        bestPractices: ['Manual security audit recommended'],
        overallScore: 50
      };
    }
  }

  /**
   * Generate a human-readable audit report from analysis results
   * @param {Object} analysis - Structured analysis from analyzeContract
   * @returns {string} Markdown-formatted audit report
   */
  async generateReport(analysis) {
    try {
      const message = await this.client.messages.create({
        model: this.model,
        max_tokens: 2048,
        messages: [
          {
            role: 'user',
            content: `Generate a concise, professional Markdown audit report from this analysis JSON. 
Include sections: Executive Summary, Findings (with severity badges), Recommendations, Score.
Keep it under 500 words.\n\n${JSON.stringify(analysis, null, 2)}`
          }
        ]
      });

      return message.content[0].text;
    } catch (error) {
      console.error('Report generation error:', error.message);
      return `# Audit Report\n\n**Contract:** ${analysis.contractAddress}\n**Risk Level:** ${analysis.riskLevel}\n**Score:** ${analysis.overallScore}/100\n\n${analysis.summary}`;
    }
  }
}

module.exports = ClaudeAnalyzer;
