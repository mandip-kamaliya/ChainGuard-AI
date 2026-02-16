import { useState } from 'react';
import { Wallet, LogOut, ExternalLink } from 'lucide-react';

function WalletConnect() {
    const [account, setAccount] = useState(null);
    const [connecting, setConnecting] = useState(false);

    const connect = async () => {
        if (!window.ethereum) {
            alert('Please install MetaMask to connect your wallet');
            return;
        }

        setConnecting(true);
        try {
            const accounts = await window.ethereum.request({
                method: 'eth_requestAccounts'
            });

            if (accounts.length > 0) {
                setAccount(accounts[0]);

                // Switch to Localhost (Anvil)
                try {
                    await window.ethereum.request({
                        method: 'wallet_switchEthereumChain',
                        params: [{ chainId: '0x7a69' }] // Localhost 31337
                    });
                } catch (switchError) {
                    // Add Localhost if not available
                    if (switchError.code === 4902) {
                        await window.ethereum.request({
                            method: 'wallet_addEthereumChain',
                            params: [{
                                chainId: '0x7a69',
                                chainName: 'Anvil Localhost',
                                rpcUrls: ['http://127.0.0.1:8545'],
                                nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
                                blockExplorerUrls: []
                            }]
                        });
                    }
                }
            }
        } catch (err) {
            console.error('Wallet connect error:', err);
        } finally {
            setConnecting(false);
        }
    };

    const disconnect = () => {
        setAccount(null);
    };

    const truncateAddress = (addr) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

    if (account) {
        return (
            <div style={{ marginTop: '8px' }}>
                <button className="wallet-btn" onClick={disconnect} style={{ width: '100%' }}>
                    <span className="wallet-address">{truncateAddress(account)}</span>
                    <LogOut size={14} />
                </button>
            </div>
        );
    }

    return (
        <div style={{ marginTop: '8px' }}>
            <button
                className="wallet-btn"
                onClick={connect}
                disabled={connecting}
                style={{ width: '100%' }}
            >
                <Wallet size={14} />
                <span>{connecting ? 'Connecting...' : 'Connect Wallet'}</span>
            </button>
        </div>
    );
}

export default WalletConnect;
