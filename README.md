# Foundry DeFi Stablecoin Protocol

> A production-grade decentralized stablecoin protocol with comprehensive testing and security features

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue.svg)
![Foundry](https://img.shields.io/badge/Foundry-Latest-red.svg)
![Coverage](https://img.shields.io/badge/Coverage-96.54%25-brightgreen.svg)
![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

**Built following Patrick Collins' Foundry Fundamentals course at Cyfrin Updraft**

## Overview

This protocol implements an over-collateralized stablecoin system enabling users to mint USD-pegged tokens against crypto assets. The system maintains price stability through algorithmic liquidations and real-time oracle price feeds.

### Key Features
- **Multi-collateral support** (WETH, WBTC)
- **Chainlink oracle integration** with staleness protection
- **Automated liquidation engine** for protocol safety
- **96.54% test coverage** with invariant testing
- **Gas-optimized** smart contracts

## Architecture

```
src/
├── DSCEngine.sol              # Core protocol logic
├── DecentralizedStableCoin.sol # ERC20 stablecoin implementation  
└── libraries/
    └── OracleLib.sol          # Price feed utilities with safety checks
```

### Protocol Mechanics

1. **Collateral Deposit** - Users deposit approved tokens (WETH/WBTC)
2. **DSC Minting** - Mint stablecoins up to 50% of collateral value
3. **Health Monitoring** - Automated tracking of collateralization ratios
4. **Liquidation** - Underwater positions liquidated to maintain protocol solvency

## Test Coverage

Comprehensive testing strategy achieving **96.54% overall coverage**:

```
┌─────────────────────────────────┬──────────────────┬──────────────────┬────────────────┬─────────────────┐
│ Contract                        │ Lines            │ Statements       │ Branches       │ Functions       │
├─────────────────────────────────┼──────────────────┼──────────────────┼────────────────┼─────────────────┤
│ DSCEngine                       │ 94.78%           │ 94.59%           │ 68.75%         │ 100%            │
│ DecentralizedStableCoin         │ 100%             │ 100%             │ 100%           │ 100%            │
│ OracleLib                       │ 100%             │ 100%             │ 100%           │ 100%            │
│ Total                           │ 96.54%           │ 96.44%           │ 80.65%         │ 100%            │
└─────────────────────────────────┴──────────────────┴──────────────────┴────────────────┴─────────────────┘
```

### Testing Approach
- **Unit Tests** - Individual function validation
- **Integration Tests** - Cross-contract interaction testing
- **Invariant Testing** - Protocol-level guarantees with fuzzing
- **Edge Case Coverage** - Security-focused boundary testing

**Critical Invariant:**
```solidity
// Protocol must always remain overcollateralized
assert(totalCollateralValueInUsd >= totalDscMinted);
```

## Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- Git

### Installation & Testing
```bash
git clone https://github.com/YOUR_USERNAME/foundry-defi-stablecoin
cd foundry-defi-stablecoin
forge install
forge test
```

### Coverage Analysis
```bash
forge coverage --report debug
```

### Local Deployment
```bash
# Start local blockchain
anvil

# Deploy contracts
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

## Security Features

- **Over-collateralization** requirements (200% minimum)
- **Liquidation threshold** at 150% to maintain protocol health
- **Oracle price validation** with staleness and heartbeat checks
- **Reentrancy protection** on all state-changing functions
- **Comprehensive input validation** across all user interactions

## Protocol Parameters

```
┌─────────────────────────┬─────────────┬──────────────────────────────────┐
│ Parameter               │ Value       │ Purpose                          │
├─────────────────────────┼─────────────┼──────────────────────────────────┤
│ Collateralization Ratio │ 200%        │ Minimum backing requirement      │
│ Liquidation Threshold   │ 150%        │ Trigger point for liquidations   │
│ Liquidation Bonus       │ 10%         │ Incentive for liquidators        │
│ Price Feed Timeout      │ 3 hours     │ Oracle staleness protection      │
└─────────────────────────┴─────────────┴──────────────────────────────────┘
```

## Technology Stack

- **Solidity 0.8.20** - Smart contract development
- **Foundry** - Development framework and testing
- **Chainlink** - Decentralized oracle network
- **OpenZeppelin** - Security-audited contract libraries

## Educational Context

This project was built following **Patrick Collins' Foundry Fundamentals course** at **Cyfrin Updraft**, demonstrating:

- Advanced DeFi protocol design patterns
- Production-grade testing methodologies
- Smart contract security best practices
- Professional development workflows

**Huge thanks to Patrick Collins (@PatrickAlphaC) and the Cyfrin team for world-class Web3 education!**

### Skills Demonstrated
✅ **Smart Contract Development** - Complex DeFi protocol implementation  
✅ **Testing Excellence** - 96.54% coverage with invariant testing  
✅ **Security Awareness** - Oracle integration and liquidation mechanisms  
✅ **Code Quality** - Clean, documented, and maintainable codebase  
✅ **DeFi Understanding** - Collateralization, liquidations, and stability mechanisms  

## Learning Resources

- **Cyfrin Updraft**: [updraft.cyfrin.io](https://updraft.cyfrin.io)
- **Patrick Collins**: [@PatrickAlphaC](https://twitter.com/PatrickAlphaC)
- **Course Materials**: Advanced Foundry
- **Documentation**: [Foundry Book](https://book.getfoundry.sh)

## License

MIT License - See [LICENSE](LICENSE) file for details

---

**Built with ❤️ following Patrick Collins' expert guidance at Cyfrin Updraft**

*Demonstrating professional-grade DeFi development skills and comprehensive testing practices*