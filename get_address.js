const { ethers } = require('ethers');
require('dotenv').config();

async function main() {
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
        console.error("PRIVATE_KEY not found in .env");
        return;
    }

    const wallet = new ethers.Wallet(privateKey);
    console.log("ADDRESS=" + wallet.address);
    const fs = require('fs');
    fs.writeFileSync('address.txt', wallet.address);
}

main().catch(console.error);
