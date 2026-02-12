const Database = require('better-sqlite3');
const path = require('path');

class ScanDatabase {
    constructor(dbPath) {
        const resolvedPath = dbPath || path.join(__dirname, '..', 'data', 'chainguard.db');

        // Ensure data directory exists
        const fs = require('fs');
        const dir = path.dirname(resolvedPath);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        this.db = new Database(resolvedPath);
        this.db.pragma('journal_mode = WAL');
        this._initTables();
    }

    _initTables() {
        this.db.exec(`
      CREATE TABLE IF NOT EXISTS scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_address TEXT NOT NULL,
        contract_name TEXT DEFAULT 'Unknown',
        risk_level TEXT DEFAULT 'UNKNOWN',
        overall_score INTEGER DEFAULT 0,
        critical_count INTEGER DEFAULT 0,
        high_count INTEGER DEFAULT 0,
        medium_count INTEGER DEFAULT 0,
        low_count INTEGER DEFAULT 0,
        ipfs_hash TEXT,
        report_id INTEGER,
        certificate_id INTEGER,
        tx_hash TEXT,
        source_verified INTEGER DEFAULT 0,
        analysis_json TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS monitored_contracts (
        address TEXT PRIMARY KEY,
        name TEXT DEFAULT 'Unknown',
        deployer TEXT,
        registered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_scan DATETIME,
        scan_count INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        scan_interval INTEGER DEFAULT 3600
      );

      CREATE TABLE IF NOT EXISTS alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_address TEXT NOT NULL,
        severity TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        resolved INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_scans_address ON scans(contract_address);
      CREATE INDEX IF NOT EXISTS idx_scans_risk ON scans(risk_level);
      CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity);
    `);
    }

    // ========== Scans ==========

    saveScan(scan) {
        const stmt = this.db.prepare(`
      INSERT INTO scans (contract_address, contract_name, risk_level, overall_score,
        critical_count, high_count, medium_count, low_count,
        ipfs_hash, report_id, certificate_id, tx_hash, source_verified, analysis_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

        const result = stmt.run(
            scan.contractAddress,
            scan.contractName || 'Unknown',
            scan.riskLevel || 'UNKNOWN',
            scan.overallScore || 0,
            scan.critical || 0,
            scan.high || 0,
            scan.medium || 0,
            scan.low || 0,
            scan.ipfsHash || null,
            scan.reportId || null,
            scan.certificateId || null,
            scan.txHash || null,
            scan.sourceVerified ? 1 : 0,
            scan.analysisJson ? JSON.stringify(scan.analysisJson) : null
        );

        return result.lastInsertRowid;
    }

    getRecentScans(limit = 20) {
        return this.db.prepare(`
      SELECT * FROM scans ORDER BY created_at DESC LIMIT ?
    `).all(limit);
    }

    getScansByContract(address) {
        return this.db.prepare(`
      SELECT * FROM scans WHERE contract_address = ? ORDER BY created_at DESC
    `).all(address);
    }

    getScanById(id) {
        return this.db.prepare('SELECT * FROM scans WHERE id = ?').get(id);
    }

    // ========== Monitored Contracts ==========

    addMonitoredContract(contract) {
        const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO monitored_contracts (address, name, deployer, scan_interval)
      VALUES (?, ?, ?, ?)
    `);
        stmt.run(contract.address, contract.name || 'Unknown', contract.deployer || null, contract.scanInterval || 3600);
    }

    updateLastScan(address) {
        this.db.prepare(`
      UPDATE monitored_contracts SET last_scan = CURRENT_TIMESTAMP, scan_count = scan_count + 1
      WHERE address = ?
    `).run(address);
    }

    getMonitoredContracts() {
        return this.db.prepare('SELECT * FROM monitored_contracts WHERE is_active = 1').all();
    }

    removeContract(address) {
        this.db.prepare('UPDATE monitored_contracts SET is_active = 0 WHERE address = ?').run(address);
    }

    // ========== Alerts ==========

    saveAlert(alert) {
        const stmt = this.db.prepare(`
      INSERT INTO alerts (contract_address, severity, title, description)
      VALUES (?, ?, ?, ?)
    `);
        return stmt.run(alert.contractAddress, alert.severity, alert.title, alert.description || '').lastInsertRowid;
    }

    getRecentAlerts(limit = 50) {
        return this.db.prepare('SELECT * FROM alerts ORDER BY created_at DESC LIMIT ?').all(limit);
    }

    resolveAlert(id) {
        this.db.prepare('UPDATE alerts SET resolved = 1 WHERE id = ?').run(id);
    }

    // ========== Stats ==========

    getStats() {
        const totalScans = this.db.prepare('SELECT COUNT(*) as count FROM scans').get().count;
        const totalContracts = this.db.prepare('SELECT COUNT(*) as count FROM monitored_contracts WHERE is_active = 1').get().count;
        const criticalFindings = this.db.prepare('SELECT COUNT(*) as count FROM scans WHERE risk_level = ?').get('CRITICAL').count;
        const recentScans = this.db.prepare('SELECT COUNT(*) as count FROM scans WHERE created_at > datetime("now", "-24 hours")').get().count;

        const severityDistribution = this.db.prepare(`
      SELECT risk_level, COUNT(*) as count FROM scans GROUP BY risk_level
    `).all();

        return {
            totalScans,
            totalContracts,
            criticalFindings,
            recentScans24h: recentScans,
            severityDistribution: Object.fromEntries(severityDistribution.map(r => [r.risk_level, r.count]))
        };
    }

    close() {
        this.db.close();
    }
}

module.exports = ScanDatabase;
