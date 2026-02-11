import { Shield, AlertTriangle, Search, FileCheck } from 'lucide-react';

function StatsOverview({ stats }) {
    const cards = [
        {
            label: 'Total Scans',
            value: stats.totalScans || 0,
            icon: Search,
            color: 'blue'
        },
        {
            label: 'Contracts Monitored',
            value: stats.totalContracts || 0,
            icon: Shield,
            color: 'cyan'
        },
        {
            label: 'Critical Findings',
            value: stats.criticalFindings || 0,
            icon: AlertTriangle,
            color: 'red'
        },
        {
            label: 'Last 24h Scans',
            value: stats.recentScans24h || 0,
            icon: FileCheck,
            color: 'green'
        }
    ];

    return (
        <div className="stats-grid">
            {cards.map(({ label, value, icon: Icon, color }) => (
                <div className="stat-card" key={label}>
                    <div className={`stat-icon ${color}`}>
                        <Icon size={24} />
                    </div>
                    <div>
                        <div className="stat-value">{value}</div>
                        <div className="stat-label">{label}</div>
                    </div>
                </div>
            ))}
        </div>
    );
}

export default StatsOverview;
