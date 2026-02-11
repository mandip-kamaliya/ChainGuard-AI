import { PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts';

const SEVERITY_COLORS = {
    CRITICAL: '#ef4444',
    HIGH: '#f97316',
    MEDIUM: '#eab308',
    LOW: '#22c55e',
    SAFE: '#06b6d4',
    UNKNOWN: '#64748b'
};

function SeverityChart({ stats, scans }) {
    // Build pie chart data from severity distribution
    const pieData = Object.entries(stats.severityDistribution || {})
        .filter(([, count]) => count > 0)
        .map(([level, count]) => ({
            name: level,
            value: count,
            fill: SEVERITY_COLORS[level] || SEVERITY_COLORS.UNKNOWN
        }));

    // Build bar chart from recent scans
    const recentScans = (scans || []).slice(0, 10).reverse();
    const barData = recentScans.map((scan, i) => ({
        name: (scan.contractName || scan.contract_name || `Scan ${i + 1}`).slice(0, 12),
        score: scan.overallScore || scan.overall_score || 0,
        critical: scan.counts?.critical || scan.critical_count || 0,
        high: scan.counts?.high || scan.high_count || 0,
        medium: scan.counts?.medium || scan.medium_count || 0,
        low: scan.counts?.low || scan.low_count || 0,
    }));

    const customTooltip = ({ active, payload }) => {
        if (!active || !payload?.length) return null;
        return (
            <div style={{
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                borderRadius: '8px',
                padding: '10px 14px',
                fontSize: '13px',
                color: 'var(--text-primary)'
            }}>
                {payload.map(p => (
                    <div key={p.name} style={{ color: p.color || 'var(--text-primary)', marginBottom: '2px' }}>
                        {p.name}: {p.value}
                    </div>
                ))}
            </div>
        );
    };

    return (
        <div className="card">
            <div className="card-header">
                <span className="card-title">Security Analytics</span>
            </div>

            {/* Severity Distribution Pie Chart */}
            {pieData.length > 0 ? (
                <div style={{ marginBottom: '24px' }}>
                    <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginBottom: '12px', fontWeight: 500 }}>
                        Severity Distribution
                    </div>
                    <ResponsiveContainer width="100%" height={220}>
                        <PieChart>
                            <Pie
                                data={pieData}
                                cx="50%"
                                cy="50%"
                                innerRadius={50}
                                outerRadius={80}
                                paddingAngle={4}
                                dataKey="value"
                                stroke="none"
                            >
                                {pieData.map((entry, i) => (
                                    <Cell key={i} fill={entry.fill} />
                                ))}
                            </Pie>
                            <Tooltip content={customTooltip} />
                            <Legend
                                verticalAlign="bottom"
                                height={36}
                                formatter={(value) => (
                                    <span style={{ color: 'var(--text-secondary)', fontSize: '12px' }}>{value}</span>
                                )}
                            />
                        </PieChart>
                    </ResponsiveContainer>
                </div>
            ) : (
                <div className="empty-state" style={{ padding: '32px 20px' }}>
                    <div className="empty-icon">📊</div>
                    <h3>No data yet</h3>
                    <p>Charts will appear after your first scan</p>
                </div>
            )}

            {/* Scan Scores Bar Chart */}
            {barData.length > 0 && (
                <div>
                    <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginBottom: '12px', fontWeight: 500 }}>
                        Recent Scan Scores
                    </div>
                    <ResponsiveContainer width="100%" height={200}>
                        <BarChart data={barData} barSize={24}>
                            <XAxis
                                dataKey="name"
                                tick={{ fill: 'var(--text-muted)', fontSize: 11 }}
                                axisLine={{ stroke: 'var(--border)' }}
                                tickLine={false}
                            />
                            <YAxis
                                tick={{ fill: 'var(--text-muted)', fontSize: 11 }}
                                axisLine={{ stroke: 'var(--border)' }}
                                tickLine={false}
                                domain={[0, 100]}
                            />
                            <Tooltip content={customTooltip} />
                            <Bar dataKey="score" fill="url(#scoreGradient)" radius={[4, 4, 0, 0]} />
                            <defs>
                                <linearGradient id="scoreGradient" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="0%" stopColor="#3b82f6" />
                                    <stop offset="100%" stopColor="#8b5cf6" />
                                </linearGradient>
                            </defs>
                        </BarChart>
                    </ResponsiveContainer>
                </div>
            )}
        </div>
    );
}

export default SeverityChart;
