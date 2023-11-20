import '@nomicfoundation/hardhat-ethers';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-deploy';
import 'hardhat-preprocessor';
import 'hardhat-deploy-ethers';
import 'hardhat-abi-exporter';

import './tasks/accounts';

import fs from 'fs';
import { resolve } from 'path';

import { config as dotenvConfig } from 'dotenv';
import { HardhatUserConfig, task } from 'hardhat/config';

dotenvConfig({ path: resolve(__dirname, './.env') });

const remappings = fs
  .readFileSync('remappings.txt', 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((line) => line.trim().split('='));

const config: HardhatUserConfig = {
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    hardhat: {
      initialBaseFeePerGas: 0,
      accounts: {
        mnemonic: `${process.env.MNEMONIC}`,
        count: 30,
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        accountsBalance: '10000000000000000000000',
        passphrase: '',
      },
    },
    ganache: {
      url: `${process.env.GANACHE_URL}`,
      accounts: {
        mnemonic: `${process.env.MNEMONIC}`,
        count: 30,
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        accountsBalance: '10000000000000000000000',
        passphrase: '',
      },
    },
    evmTestnet: {
      url: 'https://api.testnet.evm.eosnetwork.com',
      chainId: 15557,
      accounts: [process.env.EVM_TEST_PRIVATE_KEY!],
      gas: 2000000,
    },
    evm: {
      url: 'https://api.evm.eosnetwork.com',
      chainId: 17777,
      accounts: [process.env.EVM_PRIVATE_KEY!],
      gas: 2000000,
    },
  },
  solidity: {
    version: '0.8.13',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (!line.match(/^\s*import /i)) {
          return line;
        }

        const remapping = remappings.find(([find]) => line.match('"' + find));
        if (!remapping) {
          return line;
        }

        const [find, replace] = remapping;
        return line.replace('"' + find, '"' + replace);
      },
    }),
  },
  etherscan: {
    apiKey: {
      eosevm: process.env.EOS_EVM_API_KEY!,
    },
  },
};

export default config;
