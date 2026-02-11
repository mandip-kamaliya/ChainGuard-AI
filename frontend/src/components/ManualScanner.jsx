import { useState } from 'react';
import { Search, Loader2, ExternalLink, CheckCircle, XCircle } from 'lucide-react';
import { scanContract } from '../api';

function ManualScanner({ onScanComplete }) {
    const [address, setAddress] = useState('');
    const [scanning, setScanning] = useState(false);
    const [result, setResult] = useState(null);
    const [error, setError] = useState(null);

    const handleScan = async () => {
        if (!address || !address.startsWith('0x') || address.length !== 42) {
            setError('Please enter a valid contract address (0x...)');
            return;
        }

        setScanning(true);
        setError(null);
        setResult(null);

        try {
            const data = await scanContract(address);
            setResult(data);
            onScanComplete?.();
        } catch (err) {
            setError(err.message);
        } finally {
            setScanning(false);
        }
    };

    const getSeverityClass = (level) => (level || '').toLowerCase();

    return (
        <div>
            <div className="card">
                <div className="card-header">
                    <span className="card-title">Contract Scanner</span>
                </div>

                <div className="scanner-input-group">
                    <input
                        type="text"
                        placeholder="Enter contract address (0x...)"
                        value={address}
                        onChange={(e) => setAddress(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleScan()}
                        disabled={scanning}
                    />
                    <button
                        className="btn btn-primary"
                        onClick={handleScan}
                        disabled={scanning || !address}
                    >
                        {scanning ? (
                            <>
                                <div className="spinner" />
                                Analyzing...
                            </>
                        ) : (
                            <>
                                <Search size={16} />
                                Scan Contract
                            </>
                        )}
                    </button>
                </div>

                {error && (
                    <div className="vuln-item" style={{ borderColor: 'var(--critical)' }}>
                        <XCircle size={20} color="var(--critical)" />
                        <div className="vuln-meta">
                            <div className="vuln-title" style={{ color: 'var(--critical)' }}>Scan Error</div>
                            <div className="vuln-desc">{error}</div>
                        </div>
                    </div>
                )}
            </div>

            {/* Scan Result */}
            {result && (
                <div className="scan-result">
                    <div className="result-header">
                        <div>
                            <h3 style={{ fontSize: '16px', fontWeight: 600, marginBottom: '4px' }}>
                                {result.contractName || 'Contract Analysis'}
                            </h3>
                            <div className="vuln-contract">{result.contractAddress}</div>
                            <div style={{ marginTop: '8px', display: 'flex', gap: '8px', alignItems: 'center' }}>
                                <span className={`severity-badge ${getSeverityClass(result.riskLevel)}`}>
                                    {result.riskLevel}
                                </span>
                                {result.verified && (
                                    <span style={{ fontSize: '12px', color: 'var(--low)' }}>
                                        <CheckCircle size={14} style={{ marginRight: '4px', verticalAlign: 'middle' }} />
                                        Verified Source
                                    </span>
                                )}
                                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                                    {result.duration}ms
                                </span>
                            </div>
                        </div>
                        <div style={{ textAlign: 'center' }}>
                            <div className="score">{result.overallScore || 0}</div>
                            <div className="score-label">Security Score</div>
                        </div>
                    </div>

                    {/* Vulnerability counts */}
                    <div className="stats-grid" style={{ marginBottom: '16px' }}>
                        {[
                            { label: 'Critical', value: result.counts?.critical || 0, color: 'red' },
                            { label: 'High', value: result.counts?.high || 0, color: 'orange' },
                            { label: 'Medium', value: result.counts?.medium || 0, color: 'medium' },
                            { label: 'Low', value: result.counts?.low || 0, color: 'green' }
                        ].map(({ label, value, color }) => (
                            <div className="stat-card" key={label}>
                                <div>
                                    <div className="stat-value" style={{ fontSize: '24px' }}>{value}</div>
                                    <div className="stat-label">{label}</div>
                                </div>
                            </div>
                        ))}
                    </div>

                    {/* Vulnerability list */}
                    {result.vulnerabilities?.length > 0 && (
                        <div>
                            <div className="card-title" style={{ marginBottom: '12px' }}>Findings</div>
                            <div className="vuln-feed">
                                {result.vulnerabilities.map((vuln, i) => (
                                    <div className="vuln-item" key={vuln.id || i}>
                                        <span className={`severity-badge ${getSeverityClass(vuln.severity)}`}>
                                            {vuln.severity}
                                        </span>
                                        <div className="vuln-meta">
                                            <div className="vuln-title">{vuln.title}</div>
                                            <div className="vuln-desc">{vuln.description}</div>
                                            {vuln.recommendation && (
                                                <div style={{ fontSize: '12px', color: 'var(--accent)', marginTop: '6px' }}>
                                                    💡 {vuln.recommendation}
                                                </div>
                                            )}
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}

                    {/* IPFS link */}
                    {result.ipfsHash && (
                        <div style={{ marginTop: '16px', paddingTop: '12px', borderTop: '1px solid var(--border)' }}>
                            <a
                                href={result.ipfsUrl || `https://gateway.pinata.cloud/ipfs/${result.ipfsHash}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="btn btn-outline"
                                style={{ width: 'fit-content' }}
                            >
                                <ExternalLink size={14} />
                                View Full Report on IPFS
                            </a>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}

export default ManualScanner;
