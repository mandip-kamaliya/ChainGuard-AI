import { useState, useEffect, useCallback } from 'react';
import { io } from 'socket.io-client';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3001';
const socket = io(API_URL);

export function useSocket() {
    const [connected, setConnected] = useState(false);

    useEffect(() => {
        socket.on('connect', () => setConnected(true));
        socket.on('disconnect', () => setConnected(false));
        return () => {
            socket.off('connect');
            socket.off('disconnect');
        };
    }, []);

    return { socket, connected };
}

export function useStats() {
    const [stats, setStats] = useState({
        totalScans: 0,
        totalContracts: 0,
        criticalFindings: 0,
        recentScans24h: 0,
        severityDistribution: {}
    });

    const refresh = useCallback(async () => {
        try {
            const res = await fetch(`${API_URL}/api/stats`);
            if (res.ok) setStats(await res.json());
        } catch { }
    }, []);

    useEffect(() => {
        refresh();
        const id = setInterval(refresh, 30000);
        return () => clearInterval(id);
    }, [refresh]);

    useEffect(() => {
        socket.on('stats', setStats);
        return () => socket.off('stats');
    }, []);

    return { stats, refresh };
}

export function useScans() {
    const [scans, setScans] = useState([]);
    const [loading, setLoading] = useState(true);

    const refresh = useCallback(async () => {
        try {
            const res = await fetch(`${API_URL}/api/scans?limit=50`);
            if (res.ok) {
                const data = await res.json();
                setScans(data.scans || []);
            }
        } catch { } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        refresh();
        socket.on('scanResult', (result) => {
            setScans(prev => [result, ...prev].slice(0, 50));
        });
        return () => socket.off('scanResult');
    }, [refresh]);

    return { scans, loading, refresh };
}

export function useAlerts() {
    const [alerts, setAlerts] = useState([]);

    useEffect(() => {
        fetch(`${API_URL}/api/alerts?limit=50`)
            .then(r => r.json())
            .then(d => setAlerts(d.alerts || []))
            .catch(() => { });
    }, []);

    return { alerts };
}

export async function scanContract(address) {
    const res = await fetch(`${API_URL}/api/scan`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contractAddress: address })
    });
    if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || 'Scan failed');
    }
    return res.json();
}

export async function getStatus() {
    const res = await fetch(`${API_URL}/api/status`);
    return res.json();
}

export { API_URL, socket };
