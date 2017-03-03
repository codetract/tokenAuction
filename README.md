# tokenAuction

TokenAuction is an on chain auction on ethereum for tokens. This is similar to how stock exchanges determine the opening and closing prices of stocks where huge volumes can all transact at a single price. The beta can be accessed at https://gcteth.codetract.io . Read our [whitepaper](https://launch.codetract.io) for more information.

## Overview

For this beta, the trading pair is ETH Token (tokenA) and GCT (tokenB). As only tokens are allowed, ether will need to be exchanged into ether tokens first. The auction also needs to be approved before receiving tokens. These will be prompted by the website. The price is quoted similar to that at poloniex.com where A/B=price and a price of 0.4 means you can buy 1 tokenB with 0.4 tokenA.   

The auction ends at 11:00 UTC everyday then the price will be uploaded. The computation to determine which orders are filled is done off chain and uploaded together with the price to the smart contract. The transaction to settle each order will then be sent out and the settled tokens will be automatically sent to the users. The next session should start after about 30 minutes and users can again create/cancel buy and sell orders till 11:00 UTC.

## For developers

#### Ethereum mainnet

ETH Token (tokenA) address: `0x6e01ee36b522a824609b7F7DfB5e4AA8Fbb48934`  
GCT (tokenB) address: `0x560c5528ff9886d83ae117845b180e6dcf6b5175`  
auction address: `0x48F230D47914cBE8F223344b7763f064336e8FA5`

#### Functions

##### `sellB(uint256 _price, uint256 _tokenB, address _returnAddress)`

[TokenTokenAuction.sol:163-196](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L163-L196)

##### `buyB(uint256 _price, uint256 _tokenA, address _returnAddress)`

[TokenTokenAuction.sol:198-231](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L198-L231)

##### `cancelSellB(uint256 _indexSellB)`

[TokenTokenAuction.sol:233-258](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L233-L258)

##### `cancelBuyB(uint256 _indexBuyB)`

[TokenTokenAuction.sol:260-285](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L260-L285)

##### `settleSellB(uint256 _indexSellB)`

[TokenTokenAuction.sol:358-420](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L358-L420)

##### `settleBuyB(uint256 _indexBuyB)`

[TokenTokenAuction.sol:422-489](https://github.com/codetract/tokenAuction/blob/master/contracts/TokenTokenAuction.sol#L422-L489)
