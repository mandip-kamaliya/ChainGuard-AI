import { useState, useCallback } from 'react';
import { Shield, Search, BarChart3, AlertTriangle, Bell, Settings, Wallet, Activity } from 'lucide-react';
import StatsOverview from './components/StatsOverview';
import ManualScanner from './components/ManualScanner';
import VulnerabilityFeed from './components/VulnerabilityFeed';
import SeverityChart from './components/SeverityChart';
import WalletConnect from './components/WalletConnect';
import { useSocket, useStats, useScans } from './api';
import './App.css';

const NAV_ITEMS = [
  { id: 'dashboard', label: 'Dashboard', icon: BarChart3 },
  { id: 'scanner', label: 'Scanner', icon: Search },
  { id: 'alerts', label: 'Alerts', icon: Bell },
  { id: 'activity', label: 'Activity', icon: Activity },
];

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const { connected } = useSocket();
  const { stats, refresh: refreshStats } = useStats();
  const { scans, loading: scansLoading, refresh: refreshScans } = useScans();

  const handleScanComplete = useCallback(() => {
    refreshStats();
    refreshScans();
  }, [refreshStats, refreshScans]);

  return (
    <div className="app-layout">
      {/* Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-logo">
          <div className="logo-icon">🛡️</div>
          <div>
            <h1>ChainGuard AI</h1>
            <span className="version">v2.0 · Claude Sonnet</span>
          </div>
        </div>

        <nav>
          <ul className="sidebar-nav">
            {NAV_ITEMS.map(({ id, label, icon: Icon }) => (
              <li key={id}>
                <a
                  href={`#${id}`}
                  className={activeTab === id ? 'active' : ''}
                  onClick={(e) => { e.preventDefault(); setActiveTab(id); }}
                >
                  <Icon size={18} />
                  <span>{label}</span>
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="sidebar-status">
          <div>
            <span className={`status-dot ${connected ? 'online' : 'offline'}`} />
            <span>{connected ? 'Agent Online' : 'Disconnected'}</span>
          </div>
          <WalletConnect />
        </div>
      </aside>

      {/* Main Content */}
      <main className="main-content">
        {activeTab === 'dashboard' && (
          <>
            <div className="page-header">
              <h2>Security Dashboard</h2>
              <p>Real-time smart contract security monitoring on BNB Chain</p>
            </div>
            <StatsOverview stats={stats} />
            <div className="dashboard-grid">
              <div>
                <SeverityChart stats={stats} scans={scans} />
              </div>
              <div>
                <VulnerabilityFeed scans={scans} loading={scansLoading} limit={5} />
              </div>
            </div>
          </>
        )}

        {activeTab === 'scanner' && (
          <>
            <div className="page-header">
              <h2>Manual Scanner</h2>
              <p>Scan any contract address for vulnerabilities using Claude AI</p>
            </div>
            <ManualScanner onScanComplete={handleScanComplete} />
          </>
        )}

        {activeTab === 'alerts' && (
          <>
            <div className="page-header">
              <h2>Security Alerts</h2>
              <p>Critical and high-severity findings requiring attention</p>
            </div>
            <VulnerabilityFeed
              scans={scans.filter(s =>
                s.risk_level === 'CRITICAL' || s.risk_level === 'HIGH' ||
                s.riskLevel === 'CRITICAL' || s.riskLevel === 'HIGH'
              )}
              loading={scansLoading}
              limit={50}
            />
          </>
        )}

        {activeTab === 'activity' && (
          <>
            <div className="page-header">
              <h2>Scan Activity</h2>
              <p>All scans performed by ChainGuard AI</p>
            </div>
            <VulnerabilityFeed scans={scans} loading={scansLoading} limit={50} />
          </>
        )}
      </main>
    </div>
  );
}

export default App;
