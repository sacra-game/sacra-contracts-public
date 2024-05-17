import {config as dotEnvConfig} from "dotenv";
import '@nomicfoundation/hardhat-chai-matchers';
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
// import "@nomiclabs/hardhat-web3";
// import "@nomiclabs/hardhat-solhint";
import "@typechain/hardhat";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage"
import 'hardhat-deploy';
import {task} from "hardhat/config";
import {deployContract} from "./scripts/deploy/DeployContract";
import {deployAddresses} from "./deploy_helpers/deploy-addresses";

dotEnvConfig();
// tslint:disable-next-line:no-var-requires
const argv = require('yargs/yargs')()
  .env('')
  .options({
    hardhatChainId: {
      type: "number",
      default: 31337
    },
    maticRpcUrl: {
      type: "string",
    },
    fantomRpcUrl: {
      type: "string",
    },
    sepoliaRpcUrl: {
      type: "string",
      default: 'https://sepolia.gateway.tenderly.co'
    },
    sepoliaOpRpcUrl: {
      type: "string",
      default: 'https://sepolia.optimism.io'
    },
    networkScanKey: {
      type: "string",
    },
    networkScanKeyMatic: {
      type: "string",
    },
    networkScanKeyOpSepolia: {
      type: "string",
    },
    networkScanKeyFantom: {
      type: "string",
    },
    privateKey: {
      type: "string",
      default: "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" // random account
    },
    maticForkBlock: {
      type: "number",
      default: 0
    },
    loggingEnabled: {
      type: "boolean",
      default: false
    },
  }).argv;

task("deploy1", "Deploy contract", async function (args, hre, runSuper) {
  const [signer] = await hre.ethers.getSigners();
  // tslint:disable-next-line:ban-ts-ignore
  // @ts-ignore
  await deployContract(hre, signer, args.name)
}).addPositionalParam("name", "Name of the smart contract to deploy");

export default {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      chainId: !!argv.hardhatChainId ? argv.hardhatChainId : undefined,
      timeout: 99999 * 2,
      blockGasLimit: 999_000_000,
      forking: !!argv.hardhatChainId && argv.hardhatChainId !== 31337 ? {
        url:
          argv.hardhatChainId === 137 ? argv.maticRpcUrl :
            argv.hardhatChainId === 250 ? argv.fantomRpcUrl :
              argv.hardhatChainId === 64165 ? 'https://rpc.sonic.fantom.network/' :
                undefined,
        blockNumber:
          argv.hardhatChainId === 137 ? argv.maticForkBlock !== 0 ? argv.maticForkBlock : undefined :
            undefined
      } : undefined,
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        accountsBalance: "100000000000000000000000000000"
      },
      loggingEnabled: argv.loggingEnabled,
      // chains: {
      //   778877: {
      //     hardforkHistory: {
      //       istanbul: 0,
      //     },
      //   }
      // },
    },
    matic: {
      url: argv.maticRpcUrl || '',
      chainId: 137,
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiKey: argv.networkScanKeyMatic
        }
      }
    },
    imm_test: {
      chainId: 13472,
      url: "https://rpc.testnet.immutable.com",
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiUrl: 'https://explorer.testnet.immutable.com'
        }
      }
    },
    mumbai: {
      chainId: 80001,
      url: "https://rpc-mumbai.maticvigil.com",
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiKey: argv.networkScanKeyMatic
        }
      }
    },
    sepolia: {
      chainId: 11155111,
      url: argv.sepoliaRpcUrl || '',
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiKey: argv.networkScanKey
        }
      }
    },
    op_sepolia: {
      chainId: 11155420,
      url: argv.sepoliaOpRpcUrl || '',
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiKey: argv.networkScanKeyOpSepolia
        }
      }
    },
    fantom: {
      chainId: 250,
      url: argv.fantomRpcUrl || '',
      accounts: [argv.privateKey],
      verify: {
        etherscan: {
          apiKey: argv.networkScanKeyFantom
        }
      }
    },
    sonict: {
      chainId: 64165,
      url: 'https://rpc.sonic.fantom.network/',
      accounts: [argv.privateKey],
      // verify: {
      //   etherscan: {
      //     apiKey: argv.networkScanKey
      //   }
      // }
    },
    sonic_beta: {
      chainId: 64165,
      url: 'https://rpc.sonic.fantom.network/',
      accounts: [argv.privateKey],
    },
    sonict2: {
      chainId: 64165,
      url: 'https://rpc.sonic.fantom.network/',
      accounts: [argv.privateKey],
    },
    foundry: {
      chainId: 31337,
      url: 'http://127.0.0.1:8545',
      // accounts: [EnvSetup.getEnv().privateKey], do not use it, impersonate will be broken
    },
  },
  etherscan: {
    apiKey: {
      mainnet: argv.networkScanKey,
      sepolia: argv.networkScanKey,
      polygon: argv.networkScanKeyMatic ?? argv.networkScanKey,
      polygonMumbai: argv.networkScanKeyMatic ?? argv.networkScanKey,
      skale_test: 'any',
      imm_test: 'any',
      op_sepolia: argv.networkScanKeyOpSepolia,
      sonict: "lore-public",
      sonict2: "lore-public",
      fantom: argv.networkScanKeyFantom,
      opera: argv.networkScanKeyFantom,
    },
    customChains: [
      {
        network: "skale_test",
        chainId: 1351057110,
        urls: {
          apiURL: "https://staging-fast-active-bellatrix.explorer.staging-v3.skalenodes.com/api",
          browserURL: "https://staging-fast-active-bellatrix.explorer.staging-v3.skalenodes.com"
        }
      },
      {
        network: "imm_test",
        chainId: 13472,
        urls: {
          apiURL: "https://explorer.testnet.immutable.com/api",
          browserURL: "https://explorer.testnet.immutable.com"
        }
      },
      {
        network: "op_sepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimism.etherscan.io/"
        }
      },
      {
        network: "sonict",
        chainId: 64165,
        urls: {
          apiURL: " https://api.lorescan.com/64165",
          browserURL: "https://sonicscan.io/"
        }
      },
      {
        network: "sonict2",
        chainId: 64165,
        urls: {
          apiURL: " https://api.lorescan.com/64165",
          browserURL: "https://sonicscan.io/"
        }
      }
    ]
  },
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          "evmVersion": "istanbul",
          optimizer: {
            enabled: true,
            runs: 50,
          },
          outputSelection: {
            '*': {
              '*': [
                "evm.gasEstimates",
              ]
            },
          },
        }
      },
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 9999999999
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: false,
    currency: 'USD',
    gasPrice: 21
  },
  typechain: {
    outDir: "typechain",
  },
  abiExporter: {
    path: './abi',
    runOnCompile: false,
    clear: true,
    flat: true,
    pretty: false,
  },
  sourcify: {
    enabled: true
  },
  namedAccounts: deployAddresses,
};
